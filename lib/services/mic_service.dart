/// iPhone microphone recording service using the record package
/// Provides PCM16 audio stream at 16kHz for transcription services
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class MicService {
  static final MicService _instance = MicService._internal();
  factory MicService() => _instance;
  MicService._internal();

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isRecording = false;

  final _audioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioController.stream;

  bool get isRecording => _isRecording;

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    _recorder ??= AudioRecorder();
    return await _recorder!.hasPermission();
  }

  /// Start recording from iPhone microphone
  /// Streams PCM16 audio at 16kHz to match Omi device format
  Future<void> startRecording() async {
    if (_isRecording) return;

    try {
      _recorder ??= AudioRecorder();

      // Check permission
      final hasPermission = await _recorder!.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied');
      }

      // Configure for PCM16 at 16kHz (matching Omi device format)
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 256000,
      );

      // Start streaming
      final stream = await _recorder!.startStream(config);
      
      _audioSubscription = stream.listen(
        (data) {
          if (_isRecording) {
            _audioController.add(data);
          }
        },
        onError: (error) {
          debugPrint('Mic recording error: $error');
        },
        onDone: () {
          debugPrint('Mic recording stream done');
        },
      );

      _isRecording = true;
      debugPrint('iPhone microphone recording started (PCM16 @ 16kHz)');
    } catch (e) {
      debugPrint('Failed to start microphone recording: $e');
      rethrow;
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder?.stop();
    } catch (e) {
      debugPrint('Error stopping recorder: $e');
    }

    debugPrint('iPhone microphone recording stopped');
  }

  /// Dispose resources
  void dispose() {
    stopRecording();
    _recorder?.dispose();
    _recorder = null;
    _audioController.close();
  }
}
