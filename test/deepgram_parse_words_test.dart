import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/services/deepgram_service.dart';

void main() {
  group('DeepgramService.parseWords', () {
    final dg = DeepgramService(apiKey: 'unused');

    test('splits on speaker changes and keeps turn order (A-B-A)', () {
      final segs = dg.parseWords([
        {'word': 'hi', 'punctuated_word': 'Hi', 'speaker': 0, 'start': 0.0, 'end': 0.3},
        {'word': 'there', 'punctuated_word': 'there.', 'speaker': 0, 'start': 0.3, 'end': 0.7},
        {'word': 'hello', 'punctuated_word': 'Hello', 'speaker': 1, 'start': 0.9, 'end': 1.2},
        {'word': 'ok', 'punctuated_word': 'OK.', 'speaker': 0, 'start': 1.5, 'end': 1.8},
      ]);
      expect(segs.map((s) => s.speakerId).toList(), [0, 1, 0]);
      expect(segs.map((s) => s.text).toList(), ['Hi there.', 'Hello', 'OK.']);
      expect(segs[0].startTime, 0.0);
      expect(segs[0].endTime, 0.7);
      expect(segs[2].startTime, 1.5);
    });

    test('falls back to the bare word and tolerates integer times', () {
      final segs = dg.parseWords([
        {'word': 'yes', 'speaker': 2, 'start': 1, 'end': 2},
      ]);
      expect(segs.single.text, 'yes');
      expect(segs.single.speakerId, 2);
      expect(segs.single.endTime, 2.0);
    });

    test('words without a speaker field become speaker 0', () {
      final segs = dg.parseWords([
        {'word': 'a', 'start': 0.0, 'end': 0.1},
        {'word': 'b', 'start': 0.1, 'end': 0.2},
      ]);
      expect(segs.length, 1);
      expect(segs.single.speakerId, 0);
    });
  });
}
