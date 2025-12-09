/// Direct OpenAI API service for chat
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OpenAIService {
  final String apiKey;
  final String model;
  
  OpenAIService({
    required this.apiKey,
    this.model = 'gpt-4.1-mini',
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

  /// Generate a title and summary for a conversation
  Future<Map<String, String>> summarizeConversation(String transcript) async {
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
              'content': 'You summarize conversations. Respond with JSON only: {"title": "short title", "summary": "brief summary"}'
            },
            {
              'role': 'user',
              'content': 'Summarize this conversation:\n\n$transcript'
            }
          ],
          'max_tokens': 200,
          'response_format': {'type': 'json_object'},
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final content = json['choices']?[0]?['message']?['content'];
        if (content != null) {
          final parsed = jsonDecode(content);
          return {
            'title': parsed['title'] ?? 'Untitled Conversation',
            'summary': parsed['summary'] ?? '',
          };
        }
      }
      return {'title': 'Untitled Conversation', 'summary': ''};
    } catch (e) {
      debugPrint('OpenAI summarize error: $e');
      return {'title': 'Untitled Conversation', 'summary': ''};
    }
  }
}
