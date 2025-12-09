/// Opus decoder service for converting Omi BLE audio to PCM
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;

class OpusDecoderService {
  SimpleOpusDecoder? _decoder;
  bool _isInitialized = false;
  
  // Omi device audio format
  static const int sampleRate = 16000;
  static const int channels = 1;
  
  OpusDecoderService();
  
  bool get isInitialized => _isInitialized;
  
  /// Initialize the Opus decoder
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize opus library
      initOpus(await opus_flutter.load());
      
      // Create decoder for mono 16kHz audio
      _decoder = SimpleOpusDecoder(
        sampleRate: sampleRate,
        channels: channels,
      );
      
      _isInitialized = true;
      debugPrint('Opus decoder initialized');
    } catch (e) {
      debugPrint('Failed to initialize Opus decoder: $e');
      rethrow;
    }
  }
  
  /// Decode Opus audio frame to PCM16
  /// Returns null if decoding fails
  Uint8List? decode(Uint8List opusData) {
    if (!_isInitialized || _decoder == null) {
      debugPrint('Opus decoder not initialized');
      return null;
    }
    
    try {
      // Decode opus to Int16 samples
      final pcmSamples = _decoder!.decode(input: opusData);
      
      // Convert Int16List to Uint8List (raw bytes)
      final bytes = Uint8List(pcmSamples.length * 2);
      final byteData = ByteData.sublistView(bytes);
      for (int i = 0; i < pcmSamples.length; i++) {
        byteData.setInt16(i * 2, pcmSamples[i], Endian.little);
      }
      
      return bytes;
    } catch (e) {
      debugPrint('Opus decode error: $e');
      return null;
    }
  }
  
  /// Dispose the decoder
  void dispose() {
    _decoder?.destroy();
    _decoder = null;
    _isInitialized = false;
  }
}
