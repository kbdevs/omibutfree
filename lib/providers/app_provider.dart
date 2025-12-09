/// App state provider for device, conversations, and recording
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';
import '../services/deepgram_service.dart';
import '../services/mic_service.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/whisper_service.dart';
import '../services/sherpa_service.dart';
import '../services/opus_decoder_service.dart';

/// Audio source for recording
enum AudioSource { omiDevice, phoneMic }

class AppProvider with ChangeNotifier {
  final BleService _bleService = BleService();
  final MicService _micService = MicService();
  DeepgramService? _deepgramService;
  WhisperService? _whisperService;
  SherpaService? _sherpaService;
  OpenAIService? _openaiService;
  OpusDecoderService? _opusDecoder;

  // Device state
  DeviceConnectionState _deviceState = DeviceConnectionState.disconnected;
  DeviceConnectionState get deviceState => _deviceState;
  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  // Recording state - continuous listening
  bool _isListening = false;
  bool get isListening => _isListening;
  
  // Audio source tracking
  AudioSource _audioSource = AudioSource.phoneMic;
  AudioSource get audioSource => _audioSource;
  bool get isUsingOmiDevice => _audioSource == AudioSource.omiDevice;
  bool get isUsingPhoneMic => _audioSource == AudioSource.phoneMic;
  
  // Current conversation being recorded
  Conversation? _currentConversation;
  Conversation? get currentConversation => _currentConversation;
  List<TranscriptSegment> _liveSegments = [];
  List<TranscriptSegment> get liveSegments => _liveSegments;
  
  // Silence detection for auto-save
  static const Duration silenceTimeout = Duration(minutes: 2);
  Timer? _silenceTimer;
  DateTime? _lastTranscriptTime;
  bool _hasActiveConversation = false;

  // Conversations list
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  // Chat
  List<ChatMessage> _chatMessages = [];
  List<ChatMessage> get chatMessages => _chatMessages;
  bool _isChatLoading = false;
  bool get isChatLoading => _isChatLoading;

  // Subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _audioSubscription;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      // Listen to device state changes
      _stateSubscription = _bleService.stateStream.listen((state) {
        _deviceState = state;
        
        // Auto-start listening when device connects
        if (state == DeviceConnectionState.connected && !_isListening) {
          _startListeningIfReady();
        }
        
        // Stop listening when device disconnects
        if (state == DeviceConnectionState.disconnected && _isListening && _audioSource == AudioSource.omiDevice) {
          stopListening();
        }
        
        notifyListeners();
      });

      // Load saved conversations
      await loadConversations();
    } catch (e) {
      debugPrint('AppProvider init error: $e');
    }
    
    // Try to auto-connect to saved device (with delay for Bluetooth to be ready)
    Future.delayed(const Duration(seconds: 2), () => _tryAutoConnect());
  }
  
  Future<void> _tryAutoConnect() async {
    final savedId = SettingsService.savedDeviceId;
    if (savedId.isNotEmpty) {
      debugPrint('Trying to auto-connect to saved device: $savedId');
      try {
        final success = await _bleService.connectToSavedDevice(savedId);
        if (success) {
          _batteryLevel = await _bleService.getBatteryLevel();
          notifyListeners();
          debugPrint('Auto-connected to saved device!');
        } else {
          debugPrint('Auto-connect failed - device may be out of range');
        }
      } catch (e) {
        debugPrint('Auto-connect error: $e');
      }
    }
  }

  // === Device Methods ===

  Stream<List<BleDevice>> scanForDevices() {
    return _bleService.scanForDevices();
  }

  Future<void> stopScan() async {
    await _bleService.stopScan();
  }

  Future<bool> connectToDevice(BleDevice device) async {
    final success = await _bleService.connect(device.device);
    if (success) {
      // Save device for auto-reconnect
      SettingsService.savedDeviceId = device.device.remoteId.str;
      SettingsService.savedDeviceName = device.name;
      
      _batteryLevel = await _bleService.getBatteryLevel();
      notifyListeners();
    }
    return success;
  }

  Future<void> disconnectDevice() async {
    await stopListening();
    await _bleService.disconnect();
    _batteryLevel = null;
    notifyListeners();
  }
  
  Future<void> forgetDevice() async {
    await disconnectDevice();
    SettingsService.clearSavedDevice();
    notifyListeners();
  }


  // === Continuous Listening Methods ===

  Future<void> _startListeningIfReady() async {
    if (SettingsService.hasApiKeys) {
      await startListening();
    }
  }

  /// Start continuous listening using Omi device
  Future<void> startListening() async {
    if (_deviceState != DeviceConnectionState.connected) {
      throw Exception('No Omi device connected');
    }
    await _startListeningWithSource(AudioSource.omiDevice);
  }

  /// Start listening using phone microphone (fallback when no device)
  Future<void> startListeningWithMic() async {
    await _startListeningWithSource(AudioSource.phoneMic);
  }

  /// Internal method to start listening with specified audio source
  Future<void> _startListeningWithSource(AudioSource source) async {
    if (_isListening) return;
    
    final transcriptionMode = SettingsService.transcriptionMode;
    
    // Validate API keys for cloud mode
    if (transcriptionMode == 'cloud' && !SettingsService.hasDeepgramKey) {
      throw Exception('Please configure Deepgram API key in settings or switch to local transcription');
    }

    // Start transcription service based on selected mode
    switch (transcriptionMode) {
      case 'whisper':
        debugPrint('Starting with LOCAL Whisper transcription (model: ${SettingsService.whisperModel})');
        _whisperService = WhisperService(
          model: SettingsService.whisperModel,
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Whisper error: $error'),
        );
        await _whisperService!.initialize();
        _whisperService!.startProcessing();
        break;
        
      case 'sherpa':
        debugPrint('Starting with LOCAL Sherpa-ONNX transcription (with diarization)');
        _sherpaService = SherpaService(
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Sherpa error: $error'),
        );
        await _sherpaService!.initialize();
        _sherpaService!.startProcessing();
        break;
        
      default: // 'cloud'
        debugPrint('Starting with CLOUD Deepgram transcription');
        _deepgramService = DeepgramService(
          apiKey: SettingsService.deepgramApiKey,
          language: SettingsService.language,
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Deepgram error: $error'),
          // Phone mic uses PCM 16-bit, Omi device uses Opus
          encoding: source == AudioSource.phoneMic ? 'linear16' : 'opus',
          sampleRate: source == AudioSource.phoneMic ? 16000 : 16000,
        );
        await _deepgramService!.connect();
    }

    // Start audio stream from appropriate source
    if (source == AudioSource.omiDevice) {
      await _bleService.startAudioStream();
      
      // Initialize Opus decoder if using local transcription with Omi device
      if (transcriptionMode != 'cloud') {
        _opusDecoder = OpusDecoderService();
        await _opusDecoder!.initialize();
      }
      
      _audioSubscription = _bleService.audioStream.listen((audioData) {
        // Omi device audio has a 3-byte header that needs to be trimmed
        if (audioData.length <= 3) return;
        final trimmedAudio = audioData.sublist(3);
        
        // Route to active transcription service
        switch (transcriptionMode) {
          case 'whisper':
            final pcmData = _opusDecoder?.decode(trimmedAudio);
            if (pcmData != null) _whisperService?.addAudio(pcmData);
            break;
          case 'sherpa':
            final pcmData = _opusDecoder?.decode(trimmedAudio);
            if (pcmData != null) _sherpaService?.addAudio(pcmData);
            break;
          default: // cloud
            _deepgramService?.sendAudio(trimmedAudio);
        }
      });
    } else {
      final started = await _micService.startRecording();
      if (!started) {
        await _deepgramService?.disconnect();
        _whisperService?.stopProcessing();
        _sherpaService?.stopProcessing();
        throw Exception('Failed to start microphone recording');
      }
      _audioSubscription = _micService.audioStream.listen((audioData) {
        // Route to active transcription service
        switch (transcriptionMode) {
          case 'whisper':
            _whisperService?.addAudio(audioData);
            break;
          case 'sherpa':
            _sherpaService?.addAudio(audioData);
            break;
          default: // cloud
            _deepgramService?.sendAudio(audioData);
        }
      });
    }

    _audioSource = source;
    _isListening = true;
    _startNewConversation();
    notifyListeners();
    
    debugPrint('Started continuous listening with ${source.name} ($transcriptionMode)');
  }

  void _startNewConversation() {
    _currentConversation = Conversation(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
    );
    _liveSegments = [];
    _hasActiveConversation = false;
    _lastTranscriptTime = null;
    _cancelSilenceTimer();
    debugPrint('Started new conversation: ${_currentConversation!.id}');
  }

  void _onTranscriptReceived(List<TranscriptSegment> segments) {
    if (!_isListening) return;
    
    // Add segments to current conversation
    _liveSegments.addAll(segments);
    _lastTranscriptTime = DateTime.now();
    _hasActiveConversation = true;
    
    // Reset silence timer
    _resetSilenceTimer();
    
    notifyListeners();
  }

  void _resetSilenceTimer() {
    _cancelSilenceTimer();
    
    _silenceTimer = Timer(silenceTimeout, () {
      if (_hasActiveConversation && _liveSegments.isNotEmpty) {
        debugPrint('Silence timeout reached - saving conversation');
        _saveCurrentConversation();
      }
    });
  }

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  /// Save current conversation and start a new one
  Future<void> _saveCurrentConversation() async {
    if (_currentConversation == null || _liveSegments.isEmpty) {
      _startNewConversation();
      return;
    }

    // Copy data before resetting
    final conversationToSave = _currentConversation!;
    conversationToSave.segments = List.from(_liveSegments);

    // Start new conversation immediately so listening continues
    _startNewConversation();
    notifyListeners();

    // Generate summary with OpenAI (in background)
    if (SettingsService.openaiApiKey.isNotEmpty) {
      _openaiService ??= OpenAIService(
        apiKey: SettingsService.openaiApiKey,
        model: SettingsService.openaiModel,
      );
      
      try {
        final result = await _openaiService!.summarizeConversation(
          conversationToSave.transcript,
        );
        conversationToSave.title = result['title'] ?? 'Untitled';
        conversationToSave.summary = result['summary'] ?? '';
      } catch (e) {
        debugPrint('Failed to summarize: $e');
        conversationToSave.title = 'Conversation ${conversationToSave.createdAt.toString().substring(0, 16)}';
      }
    } else {
      conversationToSave.title = 'Conversation ${conversationToSave.createdAt.toString().substring(0, 16)}';
    }

    // Save to database
    await DatabaseService.saveConversation(conversationToSave);
    await loadConversations();
    
    debugPrint('Saved conversation: ${conversationToSave.title}');
  }

  /// Manually save current conversation without waiting for silence
  Future<void> manualSaveConversation() async {
    if (_liveSegments.isNotEmpty) {
      await _saveCurrentConversation();
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    if (!_isListening) return;

    _cancelSilenceTimer();

    // Save any pending conversation
    if (_hasActiveConversation && _liveSegments.isNotEmpty) {
      await _saveCurrentConversation();
    }

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // Stop appropriate audio source
    if (_audioSource == AudioSource.omiDevice) {
      await _bleService.stopAudioStream();
    } else {
      await _micService.stopRecording();
    }
    
    // Clean up transcription services
    await _deepgramService?.disconnect();
    _deepgramService = null;
    _whisperService?.stopProcessing();
    _whisperService?.dispose();
    _whisperService = null;
    _sherpaService?.stopProcessing();
    _sherpaService?.dispose();
    _sherpaService = null;
    
    _opusDecoder?.dispose();
    _opusDecoder = null;

    _isListening = false;
    _currentConversation = null;
    _liveSegments = [];
    notifyListeners();
    
    debugPrint('Stopped continuous listening');
  }

  // === Conversations Methods ===

  Future<void> loadConversations() async {
    _conversations = await DatabaseService.getConversations();
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    await DatabaseService.deleteConversation(id);
    await loadConversations();
  }

  // === Chat Methods ===

  Future<void> sendChatMessage(String message) async {
    if (message.trim().isEmpty) return;
    if (!SettingsService.hasOpenAIKey) {
      throw Exception('Please configure OpenAI API key in settings');
    }

    // Add user message
    _chatMessages.add(ChatMessage(
      id: const Uuid().v4(),
      text: message,
      isUser: true,
      createdAt: DateTime.now(),
    ));
    _isChatLoading = true;
    notifyListeners();

    // Build context from recent conversations
    final context = _buildMemoryContext();

    // Get AI response
    _openaiService ??= OpenAIService(
      apiKey: SettingsService.openaiApiKey,
      model: SettingsService.openaiModel,
    );

    try {
      final response = await _openaiService!.chat(
        userMessage: message,
        conversationContext: context,
      );

      _chatMessages.add(ChatMessage(
        id: const Uuid().v4(),
        text: response,
        isUser: false,
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      _chatMessages.add(ChatMessage(
        id: const Uuid().v4(),
        text: 'Error: ${e.toString()}',
        isUser: false,
        createdAt: DateTime.now(),
      ));
    }

    _isChatLoading = false;
    notifyListeners();
  }

  String _buildMemoryContext() {
    if (_conversations.isEmpty) return '';

    // Use last 5 conversations as context
    final recent = _conversations.take(5);
    final buffer = StringBuffer();
    buffer.writeln('Recent memories from conversations:');
    
    for (final conv in recent) {
      buffer.writeln('---');
      buffer.writeln('Date: ${conv.createdAt.toString().substring(0, 16)}');
      if (conv.title != null) buffer.writeln('Topic: ${conv.title}');
      if (conv.summary != null) buffer.writeln('Summary: ${conv.summary}');
    }
    
    return buffer.toString();
  }

  void clearChat() {
    _chatMessages = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _audioSubscription?.cancel();
    _silenceTimer?.cancel();
    _bleService.dispose();
    _micService.dispose();
    _deepgramService?.disconnect();
    super.dispose();
  }
}
