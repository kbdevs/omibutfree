/// Direct Deepgram WebSocket service for speech-to-text
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/conversation.dart';
import 'settings_service.dart';

class DeepgramService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  
  final String apiKey;
  final String language;
  final String encoding;
  final int sampleRate;
  final Function(List<TranscriptSegment>)? onTranscript;
  final Function(String)? onError;
  
  DeepgramService({
    required this.apiKey,
    this.language = 'en',
    this.encoding = 'opus',
    this.sampleRate = 16000,
    this.onTranscript,
    this.onError,
  });

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;
    
    try {
      // Deepgram WebSocket URL with parameters
      final uri = Uri.parse(
        'wss://api.deepgram.com/v1/listen'
        '?model=nova-2'
        '&language=$language'
        '&punctuate=true'
        '&diarize=true'
        '&sample_rate=$sampleRate'
        '&encoding=$encoding'
        '&channels=1'
      );

      _channel = WebSocketChannel.connect(
        uri,
        protocols: ['token', apiKey],
      );

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          debugPrint('Deepgram WebSocket error: $error');
          onError?.call(error.toString());
          _isConnected = false;
        },
        onDone: () {
          debugPrint('Deepgram WebSocket closed');
          _isConnected = false;
        },
      );

      _isConnected = true;
      debugPrint('Connected to Deepgram (encoding: $encoding, sampleRate: $sampleRate)');
    } catch (e) {
      debugPrint('Failed to connect to Deepgram: $e');
      onError?.call(e.toString());
      _isConnected = false;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final json = jsonDecode(message as String);
      
      // Check if this is a transcript result
      if (json['type'] == 'Results') {
        final alternatives = json['channel']?['alternatives'] as List?;
        if (alternatives != null && alternatives.isNotEmpty) {
          final transcript = alternatives[0]['transcript'] as String?;
          final words = alternatives[0]['words'] as List?;
          
          // Track audio duration for cost calculation
          final duration = json['duration'] as num?;
          if (duration != null && duration > 0) {
            SettingsService.addDeepgramUsage(duration.toDouble() / 60.0); // Convert seconds to minutes
          }
          
          if (transcript != null && transcript.isNotEmpty) {
            // Convert to TranscriptSegment
            final segments = parseWords(words ?? []);
            if (segments.isNotEmpty) {
              onTranscript?.call(segments);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing Deepgram message: $e');
    }
  }

  /// Split a result's words into segments, one per *consecutive run* of the
  /// same speaker. (Grouping all words by speaker, as this used to do, merged
  /// A-B-A turns into one A and one B segment, which scrambled the transcript
  /// order and made each segment span audio from several people.)
  @visibleForTesting
  List<TranscriptSegment> parseWords(List words) {
    if (words.isEmpty) return [];

    final segments = <TranscriptSegment>[];
    var run = <dynamic>[];
    int? runSpeaker;

    void flush() {
      if (run.isEmpty) return;
      // `punctuated_word` carries punctuation/capitalisation; fall back to the
      // bare word if a response does not include it.
      final text = run
          .map((w) => (w['punctuated_word'] ?? w['word'] ?? '').toString())
          .join(' ');
      segments.add(TranscriptSegment(
        text: text,
        speakerId: runSpeaker ?? 0,
        startTime: ((run.first['start'] as num?) ?? 0).toDouble(),
        endTime: ((run.last['end'] as num?) ?? 0).toDouble(),
      ));
      run = <dynamic>[];
    }

    for (final word in words) {
      final speaker = ((word['speaker'] as num?) ?? 0).toInt();
      if (runSpeaker != null && speaker != runSpeaker) flush();
      runSpeaker = speaker;
      run.add(word);
    }
    flush();

    return segments;
  }

  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) return;
    _channel!.sink.add(audioData);
  }

  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    debugPrint('Disconnected from Deepgram');
  }
}
