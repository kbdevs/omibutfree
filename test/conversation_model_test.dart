import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/models/conversation.dart';

void main() {
  group('applyPersonNames', () {
    test('renames segments by person id and leaves others alone', () {
      TranscriptSegment seg(int id, {String? personId, String? name}) =>
          TranscriptSegment(
            text: 'x',
            speakerId: id,
            startTime: 0,
            endTime: 1,
            personId: personId,
            speakerName: name,
          );
      final c = Conversation(
        id: 'c',
        createdAt: DateTime(2026),
        segments: [
          seg(0, personId: 'a', name: 'Old'),
          seg(1, personId: 'gone', name: 'Kept'),
          seg(2),
        ],
      );
      applyPersonNames([c], {'a': 'Alice'});
      expect(c.segments[0].speakerName, 'Alice');
      expect(c.segments[1].speakerName, 'Kept');
      expect(c.segments[2].speakerName, isNull);
    });
  });

  group('TranscriptSegment', () {
    test('JSON round trip keeps speaker_name and person_id', () {
      final seg = TranscriptSegment(
        text: 'hello',
        speakerId: 2,
        startTime: 1.5,
        endTime: 3,
        speakerName: 'Alice',
        personId: 'p1',
      );
      final json = seg.toJson();
      expect(json['speaker_name'], 'Alice');
      expect(json['person_id'], 'p1');

      final back = TranscriptSegment.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(back.speakerName, 'Alice');
      expect(back.personId, 'p1');
      expect(back.speakerId, 2);
      expect(back.text, 'hello');
    });

    test('unlabeled segments leave the keys out and read back as null', () {
      final seg = TranscriptSegment(
        text: 'hi',
        speakerId: 1,
        startTime: 0,
        endTime: 1,
      );
      final json = seg.toJson();
      expect(json.containsKey('speaker_name'), isFalse);
      expect(json.containsKey('person_id'), isFalse);

      final back = TranscriptSegment.fromJson(json);
      expect(back.speakerName, isNull);
      expect(back.personId, isNull);
    });

    test('old JSON without the new keys still loads', () {
      final back = TranscriptSegment.fromJson({
        'text': 'old',
        'speaker': 3,
        'start': 0,
        'end': 1,
      });
      expect(back.speakerId, 3);
      expect(back.speakerName, isNull);
    });

    test("displayName falls back to 'Speaker N'", () {
      final unnamed =
          TranscriptSegment(text: 'a', speakerId: 4, startTime: 0, endTime: 1);
      expect(unnamed.displayName, 'Speaker 4');
      unnamed.speakerName = 'Bob';
      expect(unnamed.displayName, 'Bob');
    });
  });

  group('Conversation', () {
    Conversation build() => Conversation(
          id: 'c1',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          segments: [
            TranscriptSegment(
              text: 'Hi there',
              speakerId: 0,
              startTime: 0,
              endTime: 2,
              speakerName: 'Alice',
              personId: 'p1',
            ),
            TranscriptSegment(
              text: 'Hello',
              speakerId: 1,
              startTime: 2,
              endTime: 4,
            ),
          ],
        );

    test('transcript uses names where known and Speaker N otherwise', () {
      expect(build().transcript, 'Alice: Hi there\nSpeaker 1: Hello');
    });

    test('toJson / fromJson keeps the labels', () {
      final back = Conversation.fromJson(
        jsonDecode(jsonEncode(build().toJson())) as Map<String, dynamic>,
      );
      expect(back.segments[0].speakerName, 'Alice');
      expect(back.segments[0].personId, 'p1');
      expect(back.segments[1].speakerName, isNull);
    });

    test('fromDbRow reads labels from the stored transcript', () {
      final c = build();
      final row = {
        'id': c.id,
        'created_at': c.createdAt.millisecondsSinceEpoch,
        'title': 't',
        'summary': 's',
        'transcript': jsonEncode(c.segments.map((s) => s.toJson()).toList()),
      };
      final back = Conversation.fromDbRow(row);
      expect(back.segments[0].speakerName, 'Alice');
      expect(back.segments[0].personId, 'p1');
      expect(back.transcript, 'Alice: Hi there\nSpeaker 1: Hello');
    });
  });
}
