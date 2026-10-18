import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/models/conversation.dart';

TranscriptSegment seg(String text, int speaker, double start, double end,
        {String? name, String? personId}) =>
    TranscriptSegment(
      text: text,
      speakerId: speaker,
      startTime: start,
      endTime: end,
      speakerName: name,
      personId: personId,
    );

void main() {
  group('appendSegmentsMerged', () {
    test('one speaker pausing between results stays one block', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('So I was thinking', 0, 0.0, 2.0)]);
      appendSegmentsMerged(live, [seg('we should leave early.', 0, 3.5, 5.0)]);
      appendSegmentsMerged(live, [seg('Then grab lunch.', 0, 6.0, 7.2)]);
      expect(live.length, 1);
      expect(live.single.text,
          'So I was thinking we should leave early. Then grab lunch.');
      expect(live.single.startTime, 0.0);
      expect(live.single.endTime, 7.2);
    });

    test('a different speaker in between starts a new block', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('Hi.', 0, 0.0, 0.5)]);
      appendSegmentsMerged(live, [seg('Hello.', 1, 1.0, 1.5)]);
      appendSegmentsMerged(live, [seg('How are you?', 0, 2.0, 3.0)]);
      expect(live.map((s) => s.speakerId).toList(), [0, 1, 0]);
    });

    test('a long silence starts a new block', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('First.', 0, 0.0, 1.0)]);
      appendSegmentsMerged(live, [seg('Much later.', 0, 40.0, 41.0)]);
      expect(live.length, 2);
    });

    test('gap limit is configurable', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('a', 0, 0.0, 1.0)], maxGapSeconds: 2);
      appendSegmentsMerged(live, [seg('b', 0, 4.0, 5.0)], maxGapSeconds: 2);
      expect(live.length, 2);
    });

    test('timestamps jumping backwards (new stream) never merge', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('before', 0, 100.0, 105.0)]);
      appendSegmentsMerged(live, [seg('after reconnect', 0, 2.0, 4.0)]);
      expect(live.length, 2);
    });

    test('a small overlap with the previous block still merges', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('one', 0, 0.0, 3.0)]);
      appendSegmentsMerged(live, [seg('two', 0, 2.5, 4.0)]);
      expect(live.length, 1);
    });

    test('an overlap of more than a second does not merge', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('one', 0, 0.0, 5.0)]);
      appendSegmentsMerged(live, [seg('two', 0, 2.0, 6.0)]);
      expect(live.length, 2);
    });

    test('keeps the speaker name, taking the newest one if it changed', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('a', 0, 0.0, 1.0)]);
      appendSegmentsMerged(
          live, [seg('b', 0, 2.0, 3.0, name: 'Louis', personId: 'p1')]);
      expect(live.single.speakerName, 'Louis');
      expect(live.single.personId, 'p1');
      appendSegmentsMerged(live, [seg('c', 0, 4.0, 5.0)]);
      expect(live.single.speakerName, 'Louis', reason: 'unnamed follow-up keeps the name');
    });

    test('several segments in one call merge among themselves too', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [
        seg('one', 0, 0.0, 1.0),
        seg('two', 0, 1.5, 2.0),
        seg('three', 1, 2.5, 3.0),
      ]);
      expect(live.map((s) => s.text).toList(), ['one two', 'three']);
    });

    test('one voice flipping between two Deepgram speaker numbers merges when '
        'both are recognized as the same person', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(
          live, [seg('I think', 0, 0.0, 1.0, name: 'Louis', personId: 'p1')]);
      appendSegmentsMerged(
          live, [seg('we could go', 1, 1.8, 3.0, name: 'Louis', personId: 'p1')]);
      appendSegmentsMerged(
          live, [seg('tomorrow.', 0, 3.6, 4.4, name: 'Louis', personId: 'p1')]);
      expect(live.length, 1);
      expect(live.single.text, 'I think we could go tomorrow.');
    });

    test('different speaker numbers without a shared person do not merge', () {
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [seg('a', 0, 0.0, 1.0)]);
      appendSegmentsMerged(live, [seg('b', 1, 1.5, 2.5)]);
      expect(live.length, 2);
      appendSegmentsMerged(live, [seg('c', 2, 3.0, 4.0, personId: 'p1')]);
      appendSegmentsMerged(live, [seg('d', 3, 4.5, 5.5, personId: 'p2')]);
      expect(live.length, 4, reason: 'different people never merge');
    });

    test('mergeAdjacentSegments joins blocks that recognition just named', () {
      final live = <TranscriptSegment>[
        seg('one', 0, 0.0, 1.0),
        seg('two', 1, 1.5, 2.5),
        seg('three', 0, 3.0, 4.0),
        seg('other person', 2, 4.5, 5.5, personId: 'p9'),
      ];
      // Recognition names speakers 0 and 1 as the same person.
      for (final s in live.take(3)) {
        s.speakerName = 'Louis';
        s.personId = 'p1';
      }
      mergeAdjacentSegments(live);
      expect(live.map((s) => s.text).toList(), ['one two three', 'other person']);
      expect(live.first.startTime, 0.0);
      expect(live.first.endTime, 4.0);
    });

    test('does not modify the incoming segments', () {
      final a = seg('a', 0, 0.0, 1.0);
      final b = seg('b', 0, 2.0, 3.0);
      final live = <TranscriptSegment>[];
      appendSegmentsMerged(live, [a]);
      appendSegmentsMerged(live, [b]);
      expect(a.text, 'a');
      expect(b.text, 'b');
    });
  });
}
