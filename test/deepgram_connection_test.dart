import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/services/deepgram_service.dart';

/// A stand-in for Deepgram's streaming endpoint that records what clients send.
class FakeDeepgram {
  late final HttpServer _server;
  final connections = <WebSocket>[];

  /// Messages per connection: binary frames as `List<int>`, text as `String`.
  final received = <List<dynamic>>[];

  /// While set, upgrade requests are rejected with 401 (like a bad API key).
  bool refuse = false;

  /// How long to wait before rejecting (a handshake that hangs, then fails).
  Duration refuseDelay = Duration.zero;

  /// How many upgrade requests were rejected.
  int refused = 0;

  static Future<FakeDeepgram> start() async {
    final f = FakeDeepgram();
    f._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    f._server.listen((req) async {
      if (f.refuse) {
        await Future<void>.delayed(f.refuseDelay);
        f.refused++;
        req.response.statusCode = HttpStatus.unauthorized;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(
        req,
        protocolSelector: (p) => p.first,
      );
      final log = <dynamic>[];
      f.connections.add(ws);
      f.received.add(log);
      ws.listen(log.add, onError: (_) {}, onDone: () {});
    });
    return f;
  }

  String get url => 'ws://127.0.0.1:${_server.port}/v1/listen';

  Future<void> stop() async {
    for (final c in connections) {
      await c.close();
    }
    await _server.close(force: true);
  }
}

/// The binary (audio) frames in [log], leaving out KeepAlive text frames.
List<List<int>> audioFrames(List<dynamic> log) =>
    log.whereType<List<int>>().toList();

/// Polls until [test] is true or [timeout] passes.
Future<bool> waitFor(bool Function() test,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (test()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return test();
}

Uint8List frame() => Uint8List.fromList([1, 2, 3, 4]);

void main() {
  late FakeDeepgram server;
  setUp(() async => server = await FakeDeepgram.start());
  tearDown(() async => server.stop());

  /// Creates a service that is disconnected when the test ends, even if the
  /// test fails before its own cleanup, so no timers or sockets leak into the
  /// next test.
  DeepgramService make({
    void Function()? onReconnected,
    void Function()? onGaveUp,
    Duration reconnectBaseDelay = const Duration(milliseconds: 50),
    int maxReconnectAttempts = 10,
    Duration connectionHealthyAfter = const Duration(seconds: 5),
  }) {
    final dg = DeepgramService(
        apiKey: 'k',
        baseUrl: server.url,
        encoding: 'linear16',
        keepAliveInterval: const Duration(milliseconds: 100),
        reconnectBaseDelay: reconnectBaseDelay,
        reconnectMaxDelay: const Duration(milliseconds: 600),
        onReconnected: onReconnected,
        onGaveUp: onGaveUp,
        maxReconnectAttempts: maxReconnectAttempts,
        connectionHealthyAfter: connectionHealthyAfter,
      );
    addTearDown(dg.disconnect);
    return dg;
  }

  test('connect() during a slow disconnect() keeps the new connection', () async {
    final dg = make();
    await dg.connect();
    await waitFor(() => server.received.isNotEmpty);

    // disconnect() awaits closing the old socket; connect() runs meanwhile.
    final closing = dg.disconnect();
    await dg.connect();
    await closing;

    expect(await waitFor(() => server.received.length >= 2), isTrue);
    dg.sendAudio(frame());
    expect(await waitFor(() => audioFrames(server.received[1]).isNotEmpty), isTrue,
        reason: 'audio must reach the second connection');
    await dg.disconnect();
  });

  test('audio reaches the server', () async {
    final dg = make();
    await dg.connect();
    await waitFor(() => server.received.isNotEmpty);
    dg.sendAudio(frame());
    expect(
        await waitFor(() => audioFrames(server.received.first).isNotEmpty),
        isTrue);
    await dg.disconnect();
  });

  test('a connection closed by the server is re-opened and audio flows again',
      () async {
    var reconnects = 0;
    final dg = make(onReconnected: () => reconnects++);
    await dg.connect();
    await waitFor(() => server.connections.length == 1);

    // Deepgram drops the stream (e.g. idle timeout).
    await server.connections.first.close(4000, 'simulated drop');

    expect(await waitFor(() => server.connections.length == 2), isTrue,
        reason: 'client should open a second connection');
    expect(reconnects, 1);
    expect(await waitFor(() => dg.isConnected), isTrue);

    dg.sendAudio(frame());
    expect(await waitFor(() => audioFrames(server.received[1]).isNotEmpty), isTrue,
        reason: 'audio must reach the new connection');
    await dg.disconnect();
  });

  test('audio sent while disconnected is dropped, not queued or thrown', () async {
    // A long first back-off, so the audio below is sent while there is no
    // connection and the reconnect comes only afterwards.
    final dg = make(reconnectBaseDelay: const Duration(milliseconds: 300));
    await dg.connect();
    await waitFor(() => server.connections.length == 1);
    await server.connections.first.close();
    expect(await waitFor(() => !dg.isConnected), isTrue,
        reason: 'the client should notice the closed connection');
    expect(() => dg.sendAudio(frame()), returnsNormally);

    // After the reconnect, the dropped frame must not show up on either
    // connection; only audio sent now goes through.
    expect(await waitFor(() => server.connections.length == 2), isTrue);
    expect(await waitFor(() => dg.isConnected), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(audioFrames(server.received[0]), isEmpty);
    expect(audioFrames(server.received[1]), isEmpty,
        reason: 'a frame sent while disconnected must be dropped, not queued');
    dg.sendAudio(frame());
    expect(await waitFor(() => audioFrames(server.received[1]).length == 1),
        isTrue);
    await dg.disconnect();
  });

  test('keeps reconnecting after repeated drops', () async {
    final dg = make();
    await dg.connect();
    for (var i = 1; i <= 3; i++) {
      await waitFor(() => server.connections.length == i);
      await server.connections[i - 1].close();
    }
    expect(await waitFor(() => server.connections.length == 4), isTrue);
    await dg.disconnect();
  });

  test('disconnect() stops any further reconnecting', () async {
    // The server drops the stream, so a reconnect is scheduled (after the
    // 300 ms back-off); disconnect() before it fires must cancel it.
    final dg = make(reconnectBaseDelay: const Duration(milliseconds: 300));
    await dg.connect();
    await waitFor(() => server.connections.length == 1);
    await server.connections.first.close();
    expect(await waitFor(() => !dg.isConnected), isTrue,
        reason: 'the client should notice the closed connection');
    await dg.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(server.connections.length, 1);
    expect(dg.isConnected, isFalse);
  });

  test('sends KeepAlive text frames when no audio is flowing', () async {
    final dg = make();
    await dg.connect();
    await waitFor(() => server.connections.length == 1);
    final ok = await waitFor(
        () => server.received.first.contains('{"type":"KeepAlive"}'));
    expect(ok, isTrue);
    await dg.disconnect();
  });

  test('does not send KeepAlive while audio is flowing', () async {
    final dg = make();
    await dg.connect();
    await waitFor(() => server.connections.length == 1);
    final stop = DateTime.now().add(const Duration(milliseconds: 600));
    while (DateTime.now().isBefore(stop)) {
      dg.sendAudio(frame());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(server.received.first.whereType<String>(), isEmpty);
    await dg.disconnect();
  });

  test('gives up after maxReconnectAttempts failed reconnects and says so',
      () async {
    var gaveUp = 0;
    final dg = make(maxReconnectAttempts: 3, onGaveUp: () => gaveUp++);
    await dg.connect();
    await waitFor(() => server.connections.length == 1);

    // Deepgram drops the stream and then rejects every new connection.
    server.refuse = true;
    await server.connections.first.close();

    expect(await waitFor(() => gaveUp == 1), isTrue,
        reason: 'the owner must be told that the service stopped trying');
    expect(server.refused, 3, reason: 'exactly maxReconnectAttempts retries');
    expect(dg.isConnected, isFalse);

    // It really stopped: no more attempts, and no second notification.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(server.refused, 3);
    expect(gaveUp, 1);
    await dg.disconnect();
  });

  test('a connection that comes back before the cap is used, with no give-up',
      () async {
    var gaveUp = 0;
    final dg = make(maxReconnectAttempts: 5, onGaveUp: () => gaveUp++);
    await dg.connect();
    await waitFor(() => server.connections.length == 1);

    server.refuse = true;
    await server.connections.first.close();
    await waitFor(() => server.refused >= 2);
    server.refuse = false;

    expect(await waitFor(() => dg.isConnected), isTrue);
    expect(gaveUp, 0);
    dg.sendAudio(frame());
    expect(await waitFor(() => audioFrames(server.received.last).isNotEmpty),
        isTrue);
    await dg.disconnect();
  });

  test('connect() after giving up starts a fresh round of attempts', () async {
    var gaveUp = 0;
    final dg = make(maxReconnectAttempts: 2, onGaveUp: () => gaveUp++);
    server.refuse = true;
    await dg.connect();
    expect(await waitFor(() => gaveUp == 1), isTrue);

    server.refuse = false;
    await dg.connect();
    expect(await waitFor(() => dg.isConnected), isTrue);
    expect(gaveUp, 1);
    await dg.disconnect();
  });

  test('attempts stuck in the handshake still count towards the limit',
      () async {
    // Each attempt hangs for longer than connectionHealthyAfter and then
    // fails. Counting from when the socket was opened would call that
    // "healthy", reset the count every time, and never give up.
    var gaveUp = 0;
    final dg = make(
      maxReconnectAttempts: 2,
      connectionHealthyAfter: const Duration(milliseconds: 30),
      onGaveUp: () => gaveUp++,
    );
    server.refuse = true;
    server.refuseDelay = const Duration(milliseconds: 100);
    await dg.connect();

    expect(await waitFor(() => gaveUp == 1), isTrue);
    expect(server.refused, 3, reason: 'the first try plus two reconnects');
    await dg.disconnect();
  });
}
