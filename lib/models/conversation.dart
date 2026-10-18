/// Data models for Omi Local app

import 'dart:convert';

/// A single segment of transcribed speech
class TranscriptSegment {
  final String text;

  /// Diarization index. For Deepgram this is only stable within one
  /// listening session, so it identifies "a speaker in this conversation",
  /// not a person across conversations.
  final int speakerId;
  final double startTime;
  final double endTime;
  final bool isUser;

  /// Name of the identified/assigned person, or null if this speaker has not
  /// been recognized or labeled yet.
  String? speakerName;

  /// Id of the matching row in the `people` table (null if unlabeled).
  String? personId;

  TranscriptSegment({
    required this.text,
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    this.isUser = false,
    this.speakerName,
    this.personId,
  });

  /// The full label for text: the summarizer and dialogs. Compact chips and
  /// avatars show `S1`, `S2`, ... for an unnamed speaker instead.
  String get displayName => speakerName ?? 'Speaker $speakerId';

  Map<String, dynamic> toJson() => {
    'text': text,
    'speaker_id': speakerId,
    'start': startTime,
    'end': endTime,
    'is_user': isUser,
    if (speakerName != null) 'speaker_name': speakerName,
    if (personId != null) 'person_id': personId,
  };

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      text: json['text'] ?? '',
      speakerId: json['speaker_id'] ?? json['speaker'] ?? 0,
      startTime: (json['start'] ?? 0).toDouble(),
      endTime: (json['end'] ?? 0).toDouble(),
      isUser: json['is_user'] ?? false,
      speakerName: json['speaker_name'] as String?,
      personId: json['person_id'] as String?,
    );
  }
}

/// True if two segments are from the same voice: the same Deepgram speaker
/// number, or both recognized as the same person. (Deepgram's live diarization
/// can flip one voice between two numbers, but recognition still names both
/// as the same person.)
bool _sameVoice(TranscriptSegment a, TranscriptSegment b) =>
    a.speakerId == b.speakerId ||
    (a.personId != null && a.personId == b.personId);

/// Appends [incoming] to [target], joining a segment onto the previous one when
/// both are from the same voice and the pause between them is short.
///
/// Deepgram sends a new result after every pause, so one person talking with
/// pauses would otherwise show up as a string of small blocks. A different
/// speaker in between, or a long gap, still starts a new block. When two
/// Deepgram speaker numbers are merged because both were recognized as the same
/// person, the block keeps the earlier segment's speaker number only. (Labeling
/// that block later uses that number's voice samples; the other number's
/// samples are not linked to it.) A segment may
/// start up to one second before the previous one ended (Deepgram's word
/// timings can overlap slightly) and still merge; a larger jump backwards
/// never merges. A new Deepgram stream restarts its clock, so the app ends the
/// current conversation when the stream reconnects instead of relying on this
/// check.
void appendSegmentsMerged(
  List<TranscriptSegment> target,
  List<TranscriptSegment> incoming, {
  double maxGapSeconds = 10,
}) {
  for (final seg in incoming) {
    if (target.isNotEmpty) {
      final last = target.last;
      final gap = seg.startTime - last.endTime;
      if (_sameVoice(last, seg) &&
          gap >= -1.0 &&
          gap <= maxGapSeconds) {
        target[target.length - 1] = TranscriptSegment(
          text: '${last.text} ${seg.text}'.trim(),
          speakerId: last.speakerId,
          startTime: last.startTime,
          endTime: seg.endTime > last.endTime ? seg.endTime : last.endTime,
          isUser: last.isUser || seg.isUser,
          speakerName: seg.speakerName ?? last.speakerName,
          personId: seg.personId ?? last.personId,
        );
        continue;
      }
    }
    target.add(seg);
  }
}

/// Sets each segment's `speakerName` from [namesByPersonId] (person id to
/// current name), so a rename shows in every saved transcript. Segments whose
/// person is not in the map keep the name they have.
void applyPersonNames(
  Iterable<Conversation> conversations,
  Map<String, String> namesByPersonId,
) {
  if (namesByPersonId.isEmpty) return;
  for (final c in conversations) {
    for (final s in c.segments) {
      final name = s.personId == null ? null : namesByPersonId[s.personId];
      if (name != null) s.speakerName = name;
    }
  }
}

/// Re-applies [appendSegmentsMerged] to [segments] in place, so [segments] must
/// be a growable list (not `const []`). Used after speaker recognition names
/// segments that arrived unnamed, which can make neighboring blocks belong to
/// the same person.
void mergeAdjacentSegments(
  List<TranscriptSegment> segments, {
  double maxGapSeconds = 10,
}) {
  final merged = <TranscriptSegment>[];
  appendSegmentsMerged(merged, segments, maxGapSeconds: maxGapSeconds);
  segments
    ..clear()
    ..addAll(merged);
}

/// A person whose voice has been enrolled for automatic recognition.
class Person {
  final String id;
  String name;
  final DateTime createdAt;

  /// How many voice samples are stored for this person (more = better).
  final int sampleCount;

  Person({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sampleCount = 0,
  });

  factory Person.fromDbRow(Map<String, dynamic> row) {
    return Person(
      id: row['id'] as String,
      name: row['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sampleCount: (row['sample_count'] as int?) ?? 0,
    );
  }
}

/// A complete conversation with transcript and AI summary
class Conversation {
  final String id;
  final DateTime createdAt;
  String title;
  String summary;
  List<TranscriptSegment> segments;

  Conversation({
    required this.id,
    required this.createdAt,
    this.title = '',
    this.summary = '',
    this.segments = const [],
  });

  String get transcript {
    return segments.map((s) => '${s.displayName}: ${s.text}').join('\n');
  }

  /// Get the duration of the conversation from first to last segment
  Duration get duration {
    if (segments.isEmpty) return Duration.zero;
    final firstStart = segments.first.startTime;
    final lastEnd = segments.last.endTime;
    return Duration(milliseconds: ((lastEnd - firstStart) * 1000).round());
  }

  /// Get formatted duration string (e.g., "5m 23s")
  String get formattedDuration {
    final d = duration;
    if (d.inSeconds < 60) {
      return '${d.inSeconds}s';
    } else if (d.inMinutes < 60) {
      final mins = d.inMinutes;
      final secs = d.inSeconds % 60;
      return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
    } else {
      final hours = d.inHours;
      final mins = d.inMinutes % 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.millisecondsSinceEpoch,
    'title': title,
    'summary': summary,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at']),
      title: json['title'] ?? '',
      summary: json['summary'] ?? '',
      segments: (json['segments'] as List?)
          ?.map((s) => TranscriptSegment.fromJson(s))
          .toList() ?? [],
    );
  }

  factory Conversation.fromDbRow(Map<String, dynamic> row) {
    List<TranscriptSegment> segments = [];
    if (row['transcript'] != null && row['transcript'].isNotEmpty) {
      final decoded = jsonDecode(row['transcript']) as List;
      segments = decoded.map((s) => TranscriptSegment.fromJson(s)).toList();
    }
    return Conversation(
      id: row['id'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']),
      title: row['title'] ?? '',
      summary: row['summary'] ?? '',
      segments: segments,
    );
  }
}

/// A memory extracted from conversations
class Memory {
  final String id;
  final String content;           // "User's name is Karsten"
  final String category;          // "personal", "preference", "fact"
  final DateTime createdAt;
  final String? sourceConversationId;

  Memory({
    required this.id,
    required this.content,
    required this.category,
    required this.createdAt,
    this.sourceConversationId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'category': category,
    'created_at': createdAt.millisecondsSinceEpoch,
    'source_conversation_id': sourceConversationId,
  };

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'],
      content: json['content'],
      category: json['category'] ?? 'fact',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at']),
      sourceConversationId: json['source_conversation_id'],
    );
  }

  factory Memory.fromDbRow(Map<String, dynamic> row) {
    return Memory(
      id: row['id'],
      content: row['content'],
      category: row['category'] ?? 'fact',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']),
      sourceConversationId: row['source_conversation_id'],
    );
  }
}

/// Chat message in AI conversation
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.createdAt,
  });
}

/// A task extracted from conversations
class Task {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final DateTime createdAt;
  final String? sourceConversationId;
  bool isCompleted;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    required this.createdAt,
    this.sourceConversationId,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'due_date': dueDate?.millisecondsSinceEpoch,
    'created_at': createdAt.millisecondsSinceEpoch,
    'source_conversation_id': sourceConversationId,
    'is_completed': isCompleted ? 1 : 0,
  };

  factory Task.fromDbRow(Map<String, dynamic> row) {
    return Task(
      id: row['id'],
      title: row['title'],
      description: row['description'],
      dueDate: row['due_date'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(row['due_date']) 
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']),
      sourceConversationId: row['source_conversation_id'],
      isCompleted: row['is_completed'] == 1,
    );
  }
}
