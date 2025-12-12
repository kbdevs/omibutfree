/// App state provider for device, conversations, and recording
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';
import '../services/deepgram_service.dart';
import '../services/openai_service.dart';
import '../services/settings_service.dart';
import '../services/sherpa_service.dart';
import '../services/whisper_service.dart';
import '../services/opus_decoder_service.dart';
import '../services/notification_service.dart'; 
import 'package:audioplayers/audioplayers.dart'; 
import 'package:path_provider/path_provider.dart';
import 'dart:io';


class AppProvider with ChangeNotifier {
  final BleService _bleService = BleService();
  DeepgramService? _deepgramService; // Transcription services
  SherpaService? _sherpaService;
  WhisperService? _whisperService;
  OpenAIService? _openaiService;
  OpusDecoderService? _opusDecoder;

  // Device state
  DeviceConnectionState _deviceState = DeviceConnectionState.disconnected;
  DeviceConnectionState get deviceState => _deviceState;
  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  bool _isListening = false;
  bool get isListening => _isListening;
  
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

  // Timer for connection polling
  Timer? _reconnectTimer;
  bool _isAutoReconnectEnabled = true;

  // Hold-to-Ask AI
  DateTime? _buttonPressStartTime;
  String _aiQueryTranscript = ''; // Captured text from active transcriber
  bool _isHoldToAskActive = false;
  bool get isHoldToAskActive => _isHoldToAskActive;

  // Conversations list
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  // Chat
  List<ChatMessage> _chatMessages = [];
  List<ChatMessage> get chatMessages => _chatMessages;
  bool _isChatLoading = false;
  bool get isChatLoading => _isChatLoading;

  // Audio Test
  bool _isTestingAudio = false;
  bool get isTestingAudio => _isTestingAudio;
  
  // Model loading state
  bool _isLoadingModel = false;
  bool get isLoadingModel => _isLoadingModel;
  List<int> _testAudioBuffer = [];
  final AudioPlayer _audioPlayer = AudioPlayer(); // Added

  // Subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _buttonSubscription;

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
        
        if (state == DeviceConnectionState.disconnected) {
           if (_isListening) {
             stopListening();
           }
           // Notify user of disconnection if it was previously connected/connecting
           // (Simple check: if we are here, state shifted to disconnected)
           // We might want to track previous state to avoid initial disconnect alerts?
           // For now, let's assume if we receive this event it's a change.
           // Actually, the stream emits current state. Let's rely on _deviceState update.
           
           if (_deviceState == DeviceConnectionState.connected) {
             NotificationService().showNotification("Omi Disconnected", "Your device connection was lost.");
           }
        }
        
        _deviceState = state;
        
        notifyListeners();
      });

      // Load saved conversations
      await loadConversations();
    } catch (e) {
      debugPrint('AppProvider init error: $e');
    }
    
    // Start auto-reconnect timer
    _startReconnectTimer();
  }
  
  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isAutoReconnectEnabled) return;
      
      final savedId = SettingsService.savedDeviceId;
      if (savedId.isNotEmpty && _deviceState == DeviceConnectionState.disconnected) {
         debugPrint('Auto-reconnect: Scanning for saved device...');
         scanAndConnectToSavedDevice();
      }
    });
  }

  Future<void> scanAndConnectToSavedDevice() async {
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
    if (_isListening) return;
    
    final transcriptionMode = SettingsService.transcriptionMode;
    
    // Validate API keys for cloud mode
    if (transcriptionMode == 'cloud' && !SettingsService.hasDeepgramKey) {
      throw Exception('Please configure Deepgram API key in settings or switch to local transcription');
    }

    // Start transcription service based on selected mode
    switch (transcriptionMode) {
      case 'sherpa':
        debugPrint('Starting with LOCAL Sherpa-ONNX transcription (with diarization)');
        _isLoadingModel = true;
        notifyListeners();
        
        _sherpaService = SherpaService(
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Sherpa error: $error'),
        );
        await _sherpaService!.initialize();
        _sherpaService!.startProcessing();
        
        _isLoadingModel = false;
        break;
        
      case 'whisper':
        debugPrint('Starting with LOCAL Whisper transcription (${SettingsService.whisperModelSize})');
        _isLoadingModel = true;
        notifyListeners();
        
        _whisperService = WhisperService(
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Whisper error: $error'),
          modelSize: SettingsService.whisperModelSize,
        );
        await _whisperService!.initialize();
        _whisperService!.startProcessing();
        
        _isLoadingModel = false;
        break;
        
      default: // 'cloud'
        debugPrint('Starting with CLOUD Deepgram transcription');
        _deepgramService = DeepgramService(
          apiKey: SettingsService.deepgramApiKey,
          language: SettingsService.language,
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Deepgram error: $error'),
          encoding: 'opus',
          sampleRate: 16000,
        );
        await _deepgramService!.connect();
    }

    // Start audio stream from Omi device
    await _bleService.startAudioStream();
    
    // Initialize Opus decoder for Omi device (needed for local transcription and debug playback)
    _opusDecoder = OpusDecoderService();
    await _opusDecoder!.initialize();
    
    _audioSubscription = _bleService.audioStream.listen(_handleAudioStreamData);

    _isListening = true;
    _startNewConversation();
    notifyListeners();
    
    debugPrint('Started continuous listening with Omi device ($transcriptionMode)');
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
    
    // Check for silence to handle end-of-utterance
    // ...
    
    // Accumulate for Hold-to-Ask
    if (_isHoldToAskActive) {
      for (var segment in segments) {
         if (segment.text.isNotEmpty) {
           _aiQueryTranscript += " ${segment.text}";
         }
      }
    }

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

    // Stop audio stream
    await _bleService.stopAudioStream();
    
    // Clean up transcription services
    await _deepgramService?.disconnect();
    _deepgramService = null;
    _sherpaService?.stopProcessing();
    _sherpaService?.dispose();
    _sherpaService = null;
    _whisperService?.stopProcessing();
    _whisperService?.dispose();
    _whisperService = null;
    
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

  Future<void> startAudioTest() async {
    if (_isTestingAudio) return;
    
    // Ensure listening is active
    if (!_isListening) {
      if (SettingsService.savedDeviceId.isNotEmpty) {
          await scanAndConnectToSavedDevice();
          await Future.delayed(const Duration(seconds: 1)); // Wait for connection
      }
      if (_deviceState == DeviceConnectionState.connected) {
          await startListening();
      } else {
          notifyListeners(); // Error?
          return;
      }
    }

    debugPrint('Starting Audio Test...');
    _isTestingAudio = true;
    _testAudioBuffer.clear();
    notifyListeners();

    // Record for 3 seconds
    Future.delayed(const Duration(seconds: 3), () async {
      debugPrint('Audio Test Recording finished. Buffer size: ${_testAudioBuffer.length}');
      _isTestingAudio = false;
      notifyListeners();
      
      if (_testAudioBuffer.isNotEmpty) {
        await _playBackTestAudio();
      }
    });
  }

  Future<void> _playBackTestAudio() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/test_audio.wav');
      
      // Create WAV header
      final pcmData = Uint8List.fromList(_testAudioBuffer);
      final header = _buildWavHeader(pcmData.length);
      final wavData = BytesBuilder();
      wavData.add(header);
      wavData.add(pcmData);
      
      await tempFile.writeAsBytes(wavData.toBytes());
      debugPrint('Playing back audio test file: ${tempFile.path}');
      
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  Uint8List _buildWavHeader(int dataSize) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    final fileSize = dataSize + 36;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    
    final header = BytesBuilder();
    header.add('RIFF'.codeUnits);
    header.add(_int32ToBytes(fileSize));
    header.add('WAVE'.codeUnits);
    header.add('fmt '.codeUnits);
    header.add(_int32ToBytes(16));
    header.add(_int16ToBytes(1));
    header.add(_int16ToBytes(channels));
    header.add(_int32ToBytes(sampleRate));
    header.add(_int32ToBytes(byteRate));
    header.add(_int16ToBytes(blockAlign));
    header.add(_int16ToBytes(bitsPerSample));
    header.add('data'.codeUnits);
    header.add(_int32ToBytes(dataSize));
    return header.toBytes();
  }

  Uint8List _int32ToBytes(int value) => Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  Uint8List _int16ToBytes(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);

  Timer? _doubleTapTimer; // Keep mainly for debouncing if needed, but logic is now state-driven

  // Audio Buffering for Hold-to-Ask
  List<int> _voiceCommandBuffer = [];
  bool _isCollectingVoiceCommand = false;

  void _handleButtonPress(List<int> data) async {
    if (data.isEmpty) return;
    debugPrint("Raw Button Data (length ${data.length}): $data");
    
    if (data.length < 4) {
       debugPrint("Button Data too short, ignoring.");
       return;
    }
    
    // Parse button state exactly as Omi reference does
    // Little Endian Uint32: [2, 0, 0, 0] -> 2
    final buttonState = ByteData.view(Uint8List.fromList(data.sublist(0, 4).reversed.toList()).buffer).getUint32(0);
    debugPrint("Button State Parsed: $buttonState");

    // STATE 2: Double Tap (End/Save)
    if (buttonState == 2) {
       debugPrint("Double Tap Detected (State 2): Saving Conversation");
       if (_liveSegments.isEmpty) {
          NotificationService().showNotification("Double Tap", "No active conversation to save.");
       } else {
          NotificationService().showNotification("Double Tap", "Saving conversation...");
          await manualSaveConversation();
       }
       return;
    }

    // STATE 3: Long Press Start (Hold to Ask)
    if (buttonState == 3) {
      debugPrint("Long Press Started (State 3): Listening for AI Query");
      _buttonPressStartTime = DateTime.now();
      _isHoldToAskActive = true; 
      _aiQueryTranscript = ''; 
      
      // Start buffering audio specifically for this command
      _isCollectingVoiceCommand = true;
      _voiceCommandBuffer = [];
      
      // Ensure audio stream is active immediately
      // We don't rely only on "startListening" which might be slow.
      // We manually start the stream if not already running.
      if (!_isListening) {
         await _bleService.startAudioStream();
         // Manually subscribe if not already handling in startListening
         if (_audioSubscription == null) {
            _audioSubscription = _bleService.audioStream.listen(_handleAudioStreamData);
         }
         // Note: We don't set _isListening = true here to avoid full "Live Conv" logic yet?
         // Actually we should connect Deepgram to process this buffer LIVE if possible.
         // Let's connect Deepgram too.
         startListening(); 
      }
      
      notifyListeners();
      return;
    }

    // STATE 5: Long Press End
    if (buttonState == 5) {
      debugPrint("Long Press Ended (State 5): Processing AI Query");
      
      // Wait to capture trailing audio
      await Future.delayed(const Duration(milliseconds: 1500));
      
      _isHoldToAskActive = false;
      _isCollectingVoiceCommand = false;
      notifyListeners();

      debugPrint("Final Query Transcript: '$_aiQueryTranscript'");
      
      if (_aiQueryTranscript.trim().isEmpty) {
         debugPrint("Transcript empty. Falling back to Voice Command Buffer processing? (Not implemented fully yet)");
         // If we had a direct Voice-to-Text API that accepts File/Bytes, we would send _voiceCommandBuffer here.
         // But since we rely on Streaming STT, we hope the delay allowed Deepgram to catch up.
      }

      // Stop listening to prevent self-talk from AI response
      await stopListening();
      
      await _processAiQuery();
      _buttonPressStartTime = null;
      _voiceCommandBuffer = [];
      return;
    }
  }

  // Centralized Audio Data Handler
  void _handleAudioStreamData(Uint8List audioData) {
        // Omi device audio has a 3-byte header that needs to be trimmed
        if (audioData.length <= 3) return;
        final trimmedAudio = audioData.sublist(3);
        
        // BUFFER for Voice Command if active
        if (_isCollectingVoiceCommand) {
           _voiceCommandBuffer.addAll(trimmedAudio);
        }
        
        // Decode Opus to PCM (needed for Sherpa and Debug Playback)
        final pcmData = _opusDecoder?.decode(trimmedAudio);

        if (_isTestingAudio) {
           if (pcmData != null) _testAudioBuffer.addAll(pcmData);
        } else {
           // Route to active transcription service
           final transcriptionMode = SettingsService.transcriptionMode; // Re-fetch
           switch (transcriptionMode) {
             case 'sherpa':
               if (pcmData != null) _sherpaService?.addAudio(pcmData);
               break;
             case 'whisper':
               if (pcmData != null) _whisperService?.addAudio(pcmData);
               break;
             default: // cloud
               // Deepgram expects Opus if encoding='opus'
               // If Deepgram is connected, send it.
               if (_deepgramService != null) {
                  _deepgramService?.sendAudio(trimmedAudio);
               }
           }
        }
  }

  Future<void> _processAiQuery() async {
    final query = _aiQueryTranscript.trim();
    if (query.isEmpty) {
       NotificationService().showAiResponse("I couldn't hear that. Please try again.");
       return;
    }
    
    // Notify user we are processing
    NotificationService().showAiResponse("Processing: $query");
    
    _openaiService ??= OpenAIService(
      apiKey: SettingsService.openaiApiKey,
      model: SettingsService.openaiModel,
    );
    
    try {
      // Chat
      final response = await _openaiService!.chat(
        userMessage: query,
        conversationContext: "User asked this via Hold-to-Ask (Voice Command).",
      );
      
      debugPrint('AI Response: $response');
      NotificationService().showAiResponse(response);
      
    } catch (e) {
      debugPrint("AI Query failed: $e");
      NotificationService().showAiResponse("Failed to process question. Please try again.");
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel(); // Added
    _stateSubscription?.cancel();
    _audioSubscription?.cancel();
    _buttonSubscription?.cancel();
    _silenceTimer?.cancel();
    _bleService.dispose();
    _deepgramService?.disconnect();
    _audioPlayer.dispose();
    super.dispose();
  }
}
