/// Local Whisper transcription service using whisper.cpp
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';

class WhisperService {
  Whisper? _whisper;
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  final String model;
  final Function(List<TranscriptSegment>)? onTranscript;
  final Function(String)? onError;
  
  // Buffer for accumulating audio data
  final List<int> _audioBuffer = [];
  Timer? _processTimer;
  
  // Process audio every 5 seconds
  static const Duration processInterval = Duration(seconds: 5);
  
  // Audio format settings (matching mic_service.dart PCM16 @ 16kHz mono)
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;
  
  // Patterns to filter out from transcripts
  static final RegExp _filterPattern = RegExp(
    r'\[BLANK_AUDIO\]|\[INAUDIBLE\]|\(BLANK_AUDIO\)|\(INAUDIBLE\)',
    caseSensitive: false,
  );
  
  WhisperService({
    this.model = 'base',  // Changed from tiny to base for better quality
    this.onTranscript,
    this.onError,
  });

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  
  /// Convert string model name to WhisperModel enum
  WhisperModel _getWhisperModel(String modelName) {
    switch (modelName.toLowerCase()) {
      case 'tiny':
        return WhisperModel.tiny;
      case 'base':
        return WhisperModel.base;
      case 'small':
        return WhisperModel.small;
      case 'medium':
        return WhisperModel.medium;
      case 'large':
        return WhisperModel.largeV1;
      default:
        return WhisperModel.base;
    }
  }

  /// Initialize Whisper with the specified model
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('Initializing Whisper with model: $model');
      
      _whisper = Whisper(
        model: _getWhisperModel(model),
      );
      
      _isInitialized = true;
      debugPrint('Whisper initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize Whisper: $e');
      onError?.call('Failed to initialize Whisper: $e');
      rethrow;
    }
  }

  /// Start processing audio
  void startProcessing() {
    if (!_isInitialized) {
      onError?.call('Whisper not initialized');
      return;
    }
    
    _audioBuffer.clear();
    _isProcessing = true;
    
    // Start periodic processing
    _processTimer = Timer.periodic(processInterval, (_) => _processBuffer());
  }

  /// Add audio data to buffer (expects PCM16 format)
  void addAudio(Uint8List audioData) {
    if (!_isProcessing) return;
    _audioBuffer.addAll(audioData);
  }

  /// Create a proper WAV file from PCM data
  Future<File> _createWavFile(Uint8List pcmData) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/whisper_temp_${DateTime.now().millisecondsSinceEpoch}.wav');
    
    // WAV file header
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36; // 36 bytes for header minus 8 for RIFF/size
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    
    final header = BytesBuilder();
    
    // RIFF header
    header.add('RIFF'.codeUnits);
    header.add(_int32ToBytes(fileSize));
    header.add('WAVE'.codeUnits);
    
    // fmt subchunk
    header.add('fmt '.codeUnits);
    header.add(_int32ToBytes(16)); // Subchunk1Size for PCM
    header.add(_int16ToBytes(1)); // AudioFormat: 1 = PCM
    header.add(_int16ToBytes(channels));
    header.add(_int32ToBytes(sampleRate));
    header.add(_int32ToBytes(byteRate));
    header.add(_int16ToBytes(blockAlign));
    header.add(_int16ToBytes(bitsPerSample));
    
    // data subchunk
    header.add('data'.codeUnits);
    header.add(_int32ToBytes(dataSize));
    
    // Combine header and PCM data
    final wavData = BytesBuilder();
    wavData.add(header.toBytes());
    wavData.add(pcmData);
    
    await tempFile.writeAsBytes(wavData.toBytes());
    return tempFile;
  }
  
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }
  
  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }

  /// Process accumulated audio buffer
  Future<void> _processBuffer() async {
    if (_audioBuffer.isEmpty || !_isInitialized || _whisper == null) return;
    
    // Need at least 1 second of audio (16000 samples * 2 bytes = 32000 bytes)
    if (_audioBuffer.length < 32000) return;
    
    try {
      // Copy buffer and clear
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      
      debugPrint('Processing ${audioData.length} bytes of audio with Whisper');
      
      // Create proper WAV file
      final wavFile = await _createWavFile(audioData);
      
      // Transcribe
      final transcription = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavFile.path,
          isTranslate: false,
          isNoTimestamps: false,
          splitOnWord: true,
          language: 'en',  // English only
        ),
      );
      
      // Clean up temp file
      try {
        if (await wavFile.exists()) {
          await wavFile.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
      
      // Convert to TranscriptSegment
      if (transcription.text.isNotEmpty) {
        // Filter out BLANK_AUDIO and other noise markers
        String cleanedText = transcription.text
            .replaceAll(_filterPattern, '')
            .trim();
        
        // Only emit if there's actual content after filtering
        if (cleanedText.isNotEmpty) {
          debugPrint('Whisper transcribed: $cleanedText');
          final segment = TranscriptSegment(
            text: cleanedText,
            speakerId: 0,  // Whisper doesn't do diarization
            startTime: 0,
            endTime: 0,
          );
          onTranscript?.call([segment]);
        } else {
          debugPrint('Whisper: filtered out blank audio segment');
        }
      }
    } catch (e) {
      debugPrint('Whisper transcription error: $e');
      onError?.call('Whisper error: $e');
    }
  }

  /// Stop processing
  void stopProcessing() {
    _processTimer?.cancel();
    _processTimer = null;
    _isProcessing = false;
    
    // Process any remaining audio
    if (_audioBuffer.isNotEmpty && _audioBuffer.length >= 32000) {
      _processBuffer();
    }
    _audioBuffer.clear();
  }

  /// Dispose resources
  void dispose() {
    stopProcessing();
    _whisper = null;
    _isInitialized = false;
  }
}
