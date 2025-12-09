/// Data models for Omi Local app

import 'dart:convert';

/// A single segment of transcribed speech
class TranscriptSegment {
  final String text;
  final int speakerId;
  final double startTime;
  final double endTime;
  final bool isUser;

  TranscriptSegment({
    required this.text,
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    this.isUser = false,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'speaker_id': speakerId,
    'start': startTime,
    'end': endTime,
    'is_user': isUser,
  };

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      text: json['text'] ?? '',
      speakerId: json['speaker_id'] ?? json['speaker'] ?? 0,
      startTime: (json['start'] ?? 0).toDouble(),
      endTime: (json['end'] ?? 0).toDouble(),
      isUser: json['is_user'] ?? false,
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
    return segments.map((s) => 'Speaker ${s.speakerId}: ${s.text}').join('\n');
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
