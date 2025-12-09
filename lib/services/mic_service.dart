/// iPhone microphone service for recording when no Omi device is connected
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class MicService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamController<Uint8List>? _audioController;
  StreamSubscription? _recordSubscription;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Stream of audio data from the microphone
  Stream<Uint8List> get audioStream => 
      _audioController?.stream ?? const Stream.empty();

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording from the microphone
  /// Returns true if recording started successfully
  Future<bool> startRecording() async {
    if (_isRecording) return true;

    // Check permission
    if (!await hasPermission()) {
      debugPrint('Microphone permission not granted');
      return false;
    }

    try {
      // Create new stream controller
      _audioController?.close();
      _audioController = StreamController<Uint8List>.broadcast();

      // Configure recording for Deepgram compatibility
      // Deepgram works best with 16kHz, 16-bit PCM
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      // Start recording as a stream
      final stream = await _recorder.startStream(config);
      
      _recordSubscription = stream.listen(
        (data) {
          _audioController?.add(Uint8List.fromList(data));
        },
        onError: (error) {
          debugPrint('Mic recording error: $error');
        },
        onDone: () {
          debugPrint('Mic recording stream ended');
        },
      );

      _isRecording = true;
      debugPrint('Microphone recording started');
      return true;
    } catch (e) {
      debugPrint('Failed to start microphone recording: $e');
      return false;
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    try {
      await _recordSubscription?.cancel();
      _recordSubscription = null;
      
      await _recorder.stop();
      await _audioController?.close();
      _audioController = null;
      
      _isRecording = false;
      debugPrint('Microphone recording stopped');
    } catch (e) {
      debugPrint('Error stopping microphone recording: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await stopRecording();
    _recorder.dispose();
  }
}
