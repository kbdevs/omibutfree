import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omi_local/services/openai_service.dart';

/// Runs one chat and one summary request with [model] against a fake HTTP
/// client and returns the JSON bodies that were sent.
Future<List<Map<String, dynamic>>> _sentBodies(String model) async {
  final bodies = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(
      '{"choices":[{"message":{"content":"{}"}}]}',
      200,
    );
  });
  await http.runWithClient(() async {
    final service = OpenAIService(apiKey: 'test-key', model: model);
    await service.chat(userMessage: 'hi');
    await service.summarizeConversation('some transcript');
  }, () => client);
  return bodies;
}

void main() {
  group('OpenAIService output limit', () {
    test('gpt-6-luna sends max_completion_tokens with extra headroom', () async {
      final bodies = await _sentBodies('gpt-6-luna');
      expect(bodies, hasLength(2));

      // Chat request
      expect(bodies[0].containsKey('max_tokens'), isFalse);
      expect(bodies[0]['max_completion_tokens'], 6000);

      // Summary request keeps its JSON response format
      expect(bodies[1].containsKey('max_tokens'), isFalse);
      expect(bodies[1]['max_completion_tokens'], 4200);
      expect(bodies[1]['response_format'], {'type': 'json_object'});
    });

    test('gpt-4.1-mini keeps sending max_tokens unchanged', () async {
      final bodies = await _sentBodies('gpt-4.1-mini');
      expect(bodies, hasLength(2));

      expect(bodies[0]['max_tokens'], 1000);
      expect(bodies[0].containsKey('max_completion_tokens'), isFalse);

      expect(bodies[1]['max_tokens'], 700);
      expect(bodies[1].containsKey('max_completion_tokens'), isFalse);
      expect(bodies[1]['response_format'], {'type': 'json_object'});
    });
  });
}
