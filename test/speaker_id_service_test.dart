import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/services/settings_service.dart';
import 'package:omi_local/services/speaker_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sha256OfFile matches the known digest of a small file', () async {
    final dir = Directory.systemTemp.createTempSync('sha_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/abc.bin')..writeAsStringSync('abc');
    expect(
      await SpeakerIdService.sha256OfFile(f),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();
  });

  group('SpeakerIdService.feedPcm', () {
    test('a failed first decode still advances the timeline by one frame', () {
      final svc = SpeakerIdService();
      svc.feedPcm(null);
      // Assumed 20 ms frame at 16 kHz.
      expect(svc.buffer.durationSeconds, closeTo(0.02, 1e-9));
    });

    test('a failed decode after a good frame repeats that frame length', () {
      final svc = SpeakerIdService();
      svc.feedPcm(Uint8List(1280)); // 640 samples = 40 ms
      svc.feedPcm(null);
      expect(svc.buffer.durationSeconds, closeTo(0.08, 1e-9));
    });

    test('resetStream starts the timeline again', () {
      final svc = SpeakerIdService();
      svc.feedPcm(Uint8List(640));
      svc.resetStream();
      expect(svc.buffer.durationSeconds, 0);
    });
  });

  group('SpeakerIdService.deleteStalePartials', () {
    test('removes leftover partial downloads of the model, nothing else', () {
      final dir = Directory.systemTemp.createTempSync('partials_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/${SpeakerIdService.modelFileName}');
      File('${target.path}.111.part').writeAsStringSync('x');
      File('${target.path}.222.part').writeAsStringSync('x');
      target.writeAsStringSync('the model');
      final other = File('${dir.path}/other.onnx.333.part')..writeAsStringSync('x');
      final notPartial = File('${target.path}.444.tmp')..writeAsStringSync('x');

      SpeakerIdService.deleteStalePartials(target);

      expect(File('${target.path}.111.part').existsSync(), isFalse);
      expect(File('${target.path}.222.part').existsSync(), isFalse);
      expect(target.existsSync(), isTrue);
      expect(other.existsSync(), isTrue);
      expect(notPartial.existsSync(), isTrue);
    });

    test('keeps the partial file of a download that is still running', () {
      final dir = Directory.systemTemp.createTempSync('partials_keep_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/${SpeakerIdService.modelFileName}');
      final running = File('${target.path}.555.part')..writeAsStringSync('x');
      final stale = File('${target.path}.666.part')..writeAsStringSync('x');

      SpeakerIdService.deleteStalePartials(
        target,
        keep: {'${SpeakerIdService.modelFileName}.555.part'},
      );

      expect(running.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
    });

    test('does nothing when the model folder does not exist yet', () {
      final dir = Directory.systemTemp.createTempSync('partials_none_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/missing/${SpeakerIdService.modelFileName}');
      expect(() => SpeakerIdService.deleteStalePartials(target), returnsNormally);
    });
  });

  group('SpeakerIdService.dispose', () {
    test('initialize after dispose fails instead of downloading again', () async {
      final svc = SpeakerIdService()..dispose();
      await expectLater(svc.initialize(), throwsA(isA<StateError>()));
    });
  });
}
