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
