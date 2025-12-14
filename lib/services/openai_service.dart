/// Direct OpenAI API service for chat
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'settings_service.dart';

class OpenAIService {
  final String apiKey;
  final String model;
  
  OpenAIService({
    required this.apiKey,
    this.model = 'gpt-5-mini',
  });

  /// Chat with OpenAI using conversation context
  Future<String> chat({
    required String userMessage,
    String? conversationContext,
  }) async {
    try {
      final messages = <Map<String, String>>[];
      
      // System message with context
      String systemPrompt = 'You are a helpful AI assistant. You have access to the user\'s conversation history and memories.';
      
      if (conversationContext != null && conversationContext.isNotEmpty) {
        systemPrompt += '''

Here is the user's recent conversation history for context:

$conversationContext

Use this context to provide personalized and relevant responses. Reference specific conversations when appropriate.''';
      }
      
      messages.add({
        'role': 'system',
        'content': systemPrompt,
      });
      
      messages.add({
        'role': 'user',
        'content': userMessage,
      });

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'max_tokens': 1000,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final content = json['choices']?[0]?['message']?['content'];
        
        // Track token usage
        final usage = json['usage'];
        if (usage != null) {
          SettingsService.addOpenAIUsage(
            usage['prompt_tokens'] ?? 0,
            usage['completion_tokens'] ?? 0,
          );
        }
        
        return content ?? 'No response generated';
      } else {
        debugPrint('OpenAI API error: ${response.statusCode} ${response.body}');
        throw Exception('OpenAI API error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('OpenAI chat error: $e');
      rethrow;
    }
  }

  /// Generate a title, summary, extract memories and tasks from a conversation
  Future<Map<String, dynamic>> summarizeConversation(String transcript, {DateTime? currentTime}) async {
    final now = currentTime ?? DateTime.now();
    final timeContext = 'Current date/time: ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': '''You analyze conversations and extract key information.
$timeContext

Respond with JSON only:
{
  "title": "short descriptive title",
  "summary": "brief 1-2 sentence summary",
  "memories": ["important fact 1", "important fact 2"],
  "tasks": [
    {"title": "task description", "due_date": "2024-12-12T18:00:00"}
  ]
}

For memories, extract ONLY important facts worth remembering long-term, such as:
- Names (e.g., "User's name is Karsten")
- Preferences (e.g., "User prefers tea over coffee")
- Personal details (e.g., "User works as a software engineer")

For tasks, extract actionable items mentioned:
- Things the user needs to do (e.g., "I have to write my essay tonight" → task with due_date tonight around 6pm)
- Appointments or deadlines mentioned
- Use ISO 8601 format for due_date (or null if no time mentioned)
- Infer reasonable times: "tonight" = 6pm today, "tomorrow morning" = 9am tomorrow

If there are no notable facts/tasks, return empty arrays.
Keep each item as a short, clear statement.'''
            },
            {
              'role': 'user',
              'content': 'Analyze this conversation:\n\n$transcript'
            }
          ],
          'max_tokens': 700,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final content = json['choices']?[0]?['message']?['content'];
        
        // Track token usage
        final usage = json['usage'];
        if (usage != null) {
          SettingsService.addOpenAIUsage(
            usage['prompt_tokens'] ?? 0,
            usage['completion_tokens'] ?? 0,
          );
        }
        
        if (content != null) {
          final parsed = jsonDecode(content);
          return {
            'title': parsed['title'] ?? 'Untitled Conversation',
            'summary': parsed['summary'] ?? '',
            'memories': (parsed['memories'] as List?)?.cast<String>() ?? [],
            'tasks': parsed['tasks'] ?? [],
          };
        }
      }
      return {'title': 'Untitled Conversation', 'summary': '', 'memories': <String>[], 'tasks': []};
    } catch (e) {
      debugPrint('OpenAI summarize error: $e');
      return {'title': 'Untitled Conversation', 'summary': '', 'memories': <String>[], 'tasks': []};
    }
  }
}
