/// Whisper transcription service using Sherpa-ONNX offline recognition
/// Supports tiny and base model sizes for local speech-to-text
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../models/conversation.dart';

class WhisperService {
  sherpa.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  final Function(List<TranscriptSegment>)? onTranscript;
  final Function(String)? onError;
  
  // Audio format settings
  static const int sampleRate = 16000;
  
  // Model info - configurable size
  final String modelSize; // 'tiny' or 'base'
  
  String get modelName => 'sherpa-onnx-whisper-$modelSize';
  String get modelUrl => 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName.tar.bz2';
  
  // Audio buffer for batch processing
  List<double> _audioBuffer = [];
  Timer? _processTimer;
  static const Duration _processInterval = Duration(seconds: 3); // Process every 3 seconds
  
  WhisperService({
    this.onTranscript,
    this.onError,
    this.modelSize = 'tiny', // Default to tiny for faster loading
  });

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// Get the model directory path
  Future<String> _getModelDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/whisper_models/$modelName';
  }

  /// Check if model is downloaded
  Future<bool> _isModelDownloaded() async {
    final modelDir = await _getModelDir();
    final encoderFile = File('$modelDir/$modelSize-encoder.onnx');
    return encoderFile.existsSync();
  }

  /// Download and extract the model
  Future<void> _downloadModel() async {
    debugPrint('Downloading Whisper $modelSize model...');
    
    try {
      final modelDir = await _getModelDir();
      final modelDirPath = Directory(modelDir);
      if (!modelDirPath.existsSync()) {
        modelDirPath.createSync(recursive: true);
      }
      
      // Download tar.bz2 file
      debugPrint('Downloading from: $modelUrl');
      final response = await http.get(Uri.parse(modelUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download model: ${response.statusCode}');
      }
      
      debugPrint('Whisper model downloaded, extracting...');
      
      // Save and extract
      final archivePath = '$modelDir/model.tar.bz2';
      await File(archivePath).writeAsBytes(response.bodyBytes);
      
      // Extract using bzip2 + tar
      final bytes = await File(archivePath).readAsBytes();
      final bz2Decoded = BZip2Decoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(bz2Decoded);
      
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          // Remove the top-level directory from path
          final relativePath = filename.split('/').skip(1).join('/');
          if (relativePath.isNotEmpty) {
            final outFile = File('$modelDir/$relativePath');
            outFile.createSync(recursive: true);
            outFile.writeAsBytesSync(file.content as List<int>);
          }
        }
      }
      
      // Cleanup archive
      await File(archivePath).delete();
      debugPrint('Whisper model extraction complete');
      
    } catch (e) {
      debugPrint('Whisper model download error: $e');
      rethrow;
    }
  }

  /// Initialize Whisper with offline ASR model
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('Initializing Whisper $modelSize...');
      
      // Check if model is downloaded
      if (!await _isModelDownloaded()) {
        debugPrint('Whisper model not found, downloading...');
        await _downloadModel();
      }
      
      final modelDir = await _getModelDir();
      debugPrint('Using Whisper model from: $modelDir');
      
      // Initialize sherpa-onnx bindings first
      sherpa.initBindings();
      
      // Configure the Whisper model
      final whisperConfig = sherpa.OfflineWhisperModelConfig(
        encoder: '$modelDir/$modelSize-encoder.onnx',
        decoder: '$modelDir/$modelSize-decoder.onnx',
      );
      
      final modelConfig = sherpa.OfflineModelConfig(
        whisper: whisperConfig,
        tokens: '$modelDir/$modelSize-tokens.txt',
        debug: false,
        numThreads: 2,
      );
      
      final config = sherpa.OfflineRecognizerConfig(
        model: modelConfig,
      );
      
      _recognizer = sherpa.OfflineRecognizer(config);
      
      _isInitialized = true;
      debugPrint('Whisper $modelSize initialized successfully');
      
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
    
    _audioBuffer = [];
    _isProcessing = true;
    
    // Start periodic processing timer
    _processTimer = Timer.periodic(_processInterval, (_) => _processBuffer());
    
    debugPrint('Whisper processing started');
  }

  /// Add audio data to buffer (expects PCM16 format)
  void addAudio(Uint8List audioData) {
    if (!_isProcessing || _recognizer == null) return;
    
    try {
      // Convert PCM16 bytes to float samples
      final samples = _bytesToFloatSamples(audioData);
      _audioBuffer.addAll(samples);
    } catch (e) {
      debugPrint('Whisper audio buffer error: $e');
    }
  }
  
  /// Convert PCM16 bytes to float samples
  List<double> _bytesToFloatSamples(Uint8List bytes) {
    // Ensure we have an even number of bytes
    final validLength = bytes.length - (bytes.length % 2);
    final int16List = Int16List.view(bytes.buffer, 0, validLength ~/ 2);
    final floatSamples = <double>[];
    for (int i = 0; i < int16List.length; i++) {
      floatSamples.add(int16List[i] / 32768.0);
    }
    return floatSamples;
  }

  /// Process the audio buffer
  void _processBuffer() {
    if (!_isProcessing || _recognizer == null || _audioBuffer.isEmpty) return;
    
    try {
      // Need at least 0.5 seconds of audio to process
      final minSamples = sampleRate ~/ 2;
      if (_audioBuffer.length < minSamples) return;
      
      // Take the buffer and clear it
      final samples = Float32List.fromList(_audioBuffer.map((e) => e.toDouble()).toList());
      _audioBuffer = [];
      
      debugPrint('Processing ${samples.length} samples with Whisper...');
      
      // Create stream and process
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(sampleRate: sampleRate, samples: samples);
      _recognizer!.decode(stream);
      
      final result = _recognizer!.getResult(stream);
      stream.free();
      
      if (result.text.isNotEmpty) {
        final text = result.text.trim();
        debugPrint('Whisper recognized: $text');
        
        // Emit as segment
        final segment = TranscriptSegment(
          text: text,
          speakerId: 0,
          startTime: 0,
          endTime: 0,
        );
        
        onTranscript?.call([segment]);
      }
    } catch (e) {
      debugPrint('Whisper processing error: $e');
    }
  }

  /// Stop processing
  void stopProcessing() {
    _processTimer?.cancel();
    _processTimer = null;
    _isProcessing = false;
    
    // Process any remaining audio
    if (_audioBuffer.isNotEmpty) {
      _processBuffer();
    }
    
    debugPrint('Whisper processing stopped');
  }

  /// Dispose resources
  void dispose() {
    stopProcessing();
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
  }
}
