/// Sherpa-ONNX transcription service with real-time streaming ASR
/// Using streaming-zipformer-en-20M model for English
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import '../models/conversation.dart';

class SherpaService {
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _isInitialized = false;
  bool _isProcessing = false;
  
  final Function(List<TranscriptSegment>)? onTranscript;
  final Function(String)? onError;
  
  // Audio format settings
  static const int sampleRate = 16000;
  
  // Model info
  static const String modelName = 'sherpa-onnx-streaming-zipformer-en-20M-2023-02-17';
  static const String modelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName.tar.bz2';
  
  // State for buffering
  String _lastText = '';
  Timer? _emitTimer;
  
  SherpaService({
    this.onTranscript,
    this.onError,
  });

  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;

  /// Get the model directory path
  Future<String> _getModelDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/sherpa_models/$modelName';
  }

  /// Check if model is downloaded
  Future<bool> _isModelDownloaded() async {
    final modelDir = await _getModelDir();
    final encoderFile = File('$modelDir/encoder-epoch-99-avg-1.onnx');
    return encoderFile.existsSync();
  }

  /// Download and extract the model
  Future<void> _downloadModel() async {
    debugPrint('Downloading Sherpa-ONNX model...');
    
    try {
      final modelDir = await _getModelDir();
      final modelDirPath = Directory(modelDir);
      if (!modelDirPath.existsSync()) {
        modelDirPath.createSync(recursive: true);
      }
      
      // Download tar.bz2 file
      final response = await http.get(Uri.parse(modelUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download model: ${response.statusCode}');
      }
      
      debugPrint('Model downloaded, extracting...');
      
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
      debugPrint('Model extraction complete');
      
    } catch (e) {
      debugPrint('Model download error: $e');
      rethrow;
    }
  }

  /// Initialize Sherpa-ONNX with streaming ASR model
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      debugPrint('Initializing Sherpa-ONNX...');
      
      // Check if model is downloaded
      if (!await _isModelDownloaded()) {
        debugPrint('Model not found, downloading...');
        await _downloadModel();
      }
      
      final modelDir = await _getModelDir();
      debugPrint('Using model from: $modelDir');
      
      // Initialize sherpa-onnx bindings first
      sherpa.initBindings();
      
      // Configure the transducer model
      final transducer = sherpa.OnlineTransducerModelConfig(
        encoder: '$modelDir/encoder-epoch-99-avg-1.onnx',
        decoder: '$modelDir/decoder-epoch-99-avg-1.onnx',
        joiner: '$modelDir/joiner-epoch-99-avg-1.onnx',
      );
      
      final modelConfig = sherpa.OnlineModelConfig(
        transducer: transducer,
        tokens: '$modelDir/tokens.txt',
        debug: false,
        numThreads: 2,
      );
      
      final config = sherpa.OnlineRecognizerConfig(
        model: modelConfig,
        enableEndpoint: true,
      );
      
      _recognizer = sherpa.OnlineRecognizer(config);
      _stream = _recognizer!.createStream();
      
      _isInitialized = true;
      debugPrint('Sherpa-ONNX initialized successfully');
      
    } catch (e) {
      debugPrint('Failed to initialize Sherpa-ONNX: $e');
      onError?.call('Failed to initialize Sherpa-ONNX: $e');
      rethrow;
    }
  }

  /// Start processing audio
  void startProcessing() {
    if (!_isInitialized) {
      onError?.call('Sherpa-ONNX not initialized');
      return;
    }
    
    _lastText = '';
    _isProcessing = true;
    
    debugPrint('Sherpa-ONNX processing started');
  }

  /// Add audio data to stream (expects PCM16 format)
  void addAudio(Uint8List audioData) {
    if (!_isProcessing || _recognizer == null || _stream == null) return;
    
    try {
      // Convert PCM16 bytes to float samples
      final samples = _bytesToFloatSamples(audioData);
      
      // Feed to recognizer
      _stream!.acceptWaveform(sampleRate: sampleRate, samples: samples);
      
      // Process all ready frames
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }
      
      // Check for valid endpoint (end of sentence/utterance)
      // This is crucial to avoid emitting partial duplicates
      final isEndpoint = _recognizer!.isEndpoint(_stream!);
      
      if (isEndpoint) {
        final result = _recognizer!.getResult(_stream!);
        if (result.text.isNotEmpty) {
          _lastText = result.text;
          _checkAndEmit(); // Emit the final segment
        }
      }
    } catch (e) {
      debugPrint('Sherpa-ONNX audio processing error: $e');
    }
  }
  
  /// Convert PCM16 bytes to float samples
  Float32List _bytesToFloatSamples(Uint8List bytes) {
    // Ensure we have an even number of bytes
    final validLength = bytes.length - (bytes.length % 2);
    if (validLength == 0) return Float32List(0);
    
    // Use ByteData for safe access regardless of buffer alignment
    final byteData = ByteData.sublistView(bytes, 0, validLength);
    final numSamples = validLength ~/ 2;
    final floatSamples = Float32List(numSamples);
    
    for (int i = 0; i < numSamples; i++) {
      final int16Value = byteData.getInt16(i * 2, Endian.little);
      floatSamples[i] = int16Value / 32768.0;
    }
    return floatSamples;
  }

  /// Emit segment and reset stream
  void _checkAndEmit() {
    if (_lastText.isEmpty) return;
    
    final text = _lastText.trim();
    if (text.isEmpty) return;
    
    debugPrint('Sherpa finalized: $text');
    
    // Emit as segment
    final segment = TranscriptSegment(
      text: text,
      speakerId: 0,
      startTime: 0,
      endTime: 0,
    );
    
    onTranscript?.call([segment]);
    
    // Reset stream for next utterance
    if (_recognizer != null && _stream != null) {
      _recognizer!.reset(_stream!);
      _lastText = '';
    }
  }

  /// Stop processing
  void stopProcessing() {
    _emitTimer?.cancel();
    _emitTimer = null;
    _isProcessing = false;
    
    // Emit any remaining text
    if (_lastText.isNotEmpty) {
      _checkAndEmit();
    }
    
    debugPrint('Sherpa-ONNX processing stopped');
  }

  /// Dispose resources
  void dispose() {
    stopProcessing();
    _stream?.free();
    _recognizer?.free();
    _stream = null;
    _recognizer = null;
    _isInitialized = false;
  }
}
