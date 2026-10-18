import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/services/serial_queue.dart';

void main() {
  test('operations run one at a time, in the order added', () async {
    final q = SerialQueue();
    final log = <String>[];
    final slow = q.run(() async {
      log.add('slow start');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      log.add('slow end');
    });
    final fast = q.run(() async => log.add('fast'));
    await Future.wait([slow, fast]);
    expect(log, ['slow start', 'slow end', 'fast']);
  });

  test('returns each operation\'s result', () async {
    final q = SerialQueue();
    expect(await q.run(() async => 3), 3);
    expect(await q.run(() async => 'x'), 'x');
  });

  test('an error reaches its own caller and does not block later operations',
      () async {
    final q = SerialQueue();
    final failing = q.run<void>(() async => throw StateError('boom'));
    final after = q.run(() async => 'ok');
    await expectLater(failing, throwsStateError);
    expect(await after, 'ok');
  });
}
