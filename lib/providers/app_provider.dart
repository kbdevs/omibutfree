/// App state provider for device, conversations, and recording
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
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
import '../services/mic_service.dart';
import '../services/sdcard_sync_service.dart';
import '../services/serial_queue.dart';
import '../services/speaker_id_service.dart';
import '../services/speaker_matching.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class AppProvider with ChangeNotifier, WidgetsBindingObserver {
  final BleService _bleService = BleService();
  final MicService _micService = MicService();
  SdCardSyncService? _sdCardSyncService;

  // App lifecycle state
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  DeepgramService? _deepgramService; // Transcription services
  SherpaService? _sherpaService;
  WhisperService? _whisperService;
  OpenAIService? _openaiService;
  OpusDecoderService? _opusDecoder;
  SpeakerIdService? _speakerId; // On-device speaker recognition (Deepgram mode)

  // Device state
  DeviceConnectionState _deviceState = DeviceConnectionState.disconnected;
  DeviceConnectionState get deviceState => _deviceState;
  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  // Battery notification tracking (to avoid duplicate alerts)
  bool _notified50 = false;
  bool _notified20 = false;

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Set when cloud transcription stopped because Deepgram could not be
  /// reached again; shown on the home page until dismissed or listening is
  /// started again.
  String? _transcriptionWarning;
  String? get transcriptionWarning => _transcriptionWarning;

  void dismissTranscriptionWarning() {
    if (_transcriptionWarning == null) return;
    _transcriptionWarning = null;
    notifyListeners();
  }

  // Phone mic state
  bool _isUsingPhoneMic = false;
  bool get isUsingPhoneMic => _isUsingPhoneMic;

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
  bool _isAiQueryProcessing = false; // Pauses main conversation transcription
  bool _isProcessingButtonEvent = false; // Debounce for button events
  bool get isHoldToAskActive => _isHoldToAskActive;
  bool get isAiQueryProcessing => _isAiQueryProcessing;

  // Conversations list
  List<Conversation> _conversations = [];
  List<Conversation> get conversations => _conversations;

  // Memories list
  List<Memory> _memories = [];
  List<Memory> get memories => _memories;

  // Tasks list
  List<Task> _tasks = [];
  List<Task> get tasks => _tasks;

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

  // SD Card Sync
  bool _hasStorageSupport = false;
  bool get hasStorageSupport => _hasStorageSupport;
  SdCardSyncService? get sdCardSyncService => _sdCardSyncService;

  // Subscriptions
  StreamSubscription? _stateSubscription;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _buttonSubscription;

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    // Register app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    try {
      // Listen to device state changes
      _stateSubscription = _bleService.stateStream.listen((state) async {
        final previousState = _deviceState;
        _deviceState = state;

        // Auto-start listening when device connects (only if not using phone mic)
        if (state == DeviceConnectionState.connected &&
            !_isListening &&
            !_isUsingPhoneMic) {
          // Check for SD card storage support on any connection
          await _checkStorageSupport();
          _startListeningIfReady();
        }

        if (state == DeviceConnectionState.disconnected) {
          // Only stop listening if we were using Omi, not phone mic
          if (_isListening && !_isUsingPhoneMic) {
            stopListening();
          }

          // Notify user of disconnection if it was previously connected
          // Only show notification if app is in background
          if (previousState == DeviceConnectionState.connected &&
              _appLifecycleState != AppLifecycleState.resumed) {
            NotificationService().showNotification(
              "Omi Disconnected",
              "Your device connection was lost.",
            );
          }
        }

        notifyListeners();
      });

      // Listen to button events
      _buttonSubscription = _bleService.buttonStream.listen(_handleButtonPress);

      // Load saved conversations, memories, and tasks
      await loadConversations();
      await loadMemories();
      await loadTasks();
      // Drop old voice clips kept for labeling (see DatabaseService).
      await DatabaseService.purgeOldConversationSpeakers();
      await loadPeople();
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

      // Don't auto-reconnect when using phone mic
      if (_isUsingPhoneMic || _isListening) return;

      final savedId = SettingsService.savedDeviceId;
      if (savedId.isNotEmpty &&
          _deviceState == DeviceConnectionState.disconnected) {
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
          _checkBatteryNotification();

          // Check for SD card storage support
          await _checkStorageSupport();

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
      _checkBatteryNotification();

      // Check for SD card storage support
      await _checkStorageSupport();

      notifyListeners();
    }
    return success;
  }

  /// Check if the device supports SD card storage
  Future<void> _checkStorageSupport() async {
    _hasStorageSupport = await _bleService.hasStorageSupport();
    if (_hasStorageSupport) {
      _sdCardSyncService = SdCardSyncService(_bleService);
      debugPrint('SD card storage support detected');
    } else {
      _sdCardSyncService = null;
      debugPrint('No SD card storage support');
    }
    notifyListeners();
  }

  Future<void> disconnectDevice() async {
    await stopListening();
    await _bleService.disconnect();
    _batteryLevel = null;
    _notified50 = false;
    _notified20 = false;
    notifyListeners();
  }

  /// Check battery level and show notification at 50% and 20%
  void _checkBatteryNotification() {
    if (_batteryLevel == null) return;

    if (_batteryLevel! <= 20 && !_notified20) {
      _notified20 = true;
      if (SettingsService.notifyBatteryCritical) {
        NotificationService().showNotification(
          'Low Battery Warning',
          'Omi battery is at $_batteryLevel%. Please charge soon.',
        );
      }
    } else if (_batteryLevel! <= 50 && !_notified50) {
      _notified50 = true;
      if (SettingsService.notifyBatteryLow) {
        NotificationService().showNotification(
          'Battery Getting Low',
          'Omi battery is at $_batteryLevel%.',
        );
      }
    }

    // Reset flags when charged above thresholds
    if (_batteryLevel! > 50) {
      _notified50 = false;
      _notified20 = false;
    } else if (_batteryLevel! > 20) {
      _notified20 = false;
    }
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

    _isUsingPhoneMic = false;
    await _startTranscriptionServices(useOpusEncoding: true);

    // Start audio stream from Omi device
    await _bleService.startAudioStream();

    // Initialize Opus decoder for Omi device (needed for local transcription and debug playback)
    _opusDecoder = OpusDecoderService();
    await _opusDecoder!.initialize();

    _audioSubscription = _bleService.audioStream.listen(_handleOmiAudioData);

    _isListening = true;
    _startNewConversation();
    notifyListeners();

    debugPrint(
      'Started continuous listening with Omi device (${SettingsService.transcriptionMode})',
    );
  }

  /// Start continuous listening using iPhone microphone
  Future<void> startListeningWithPhoneMic() async {
    if (_isListening) return;

    // Check mic permission
    final hasPermission = await _micService.hasPermission();
    if (!hasPermission) {
      throw Exception(
        'Microphone permission denied. Please enable in Settings.',
      );
    }

    _isUsingPhoneMic = true;
    await _startTranscriptionServices(useOpusEncoding: false);

    // Start phone mic recording
    await _micService.startRecording();
    _audioSubscription = _micService.audioStream.listen(
      _handlePhoneMicAudioData,
    );

    _isListening = true;
    _startNewConversation();
    notifyListeners();

    debugPrint(
      'Started continuous listening with iPhone microphone (${SettingsService.transcriptionMode})',
    );
  }

  /// Initialize transcription services based on selected mode
  Future<void> _startTranscriptionServices({
    required bool useOpusEncoding,
  }) async {
    final transcriptionMode = SettingsService.transcriptionMode;
    _transcriptionWarning = null;

    // Validate API keys for cloud mode
    if (transcriptionMode == 'cloud' && !SettingsService.hasDeepgramKey) {
      throw Exception(
        'Please configure Deepgram API key in settings or switch to local transcription',
      );
    }

    // Start transcription service based on selected mode
    switch (transcriptionMode) {
      case 'sherpa':
        debugPrint(
          'Starting with LOCAL Sherpa-ONNX transcription (with diarization)',
        );
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
        debugPrint(
          'Starting with LOCAL Whisper transcription (${SettingsService.whisperModelSize})',
        );
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
        late final DeepgramService deepgram;
        deepgram = _deepgramService = DeepgramService(
          apiKey: SettingsService.deepgramApiKey,
          language: SettingsService.language,
          onTranscript: _onTranscriptReceived,
          onError: (error) => debugPrint('Deepgram error: $error'),
          onReconnected: _onDeepgramReconnected,
          onGaveUp: () => _onDeepgramGaveUp(deepgram),
          // Use linear16 for phone mic (raw PCM), opus for Omi
          encoding: useOpusEncoding ? 'opus' : 'linear16',
          sampleRate: 16000,
        );
        await _deepgramService!.connect();
        _startSpeakerId();
    }
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
    _speakerId?.session.startNewConversation();
    _conversationGen++;
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

    // Give already-recognized speakers their name straight away
    _applyKnownSpeakers(segments);

    // Add segments to current conversation
    // Deepgram answers every pause with a new result; join same-speaker runs
    // into one block. (Local engines keep their own segmentation.)
    debugPrint(
      'Transcript segments: ${segments.map((s) => "[spk ${s.speakerId} "
          "${s.startTime.toStringAsFixed(1)}-${s.endTime.toStringAsFixed(1)}s]").join(" ")}',
    );
    if (_mergesSegments) {
      appendSegmentsMerged(_liveSegments, segments);
    } else {
      _liveSegments.addAll(segments);
    }
    _scheduleSpeakerIdentification(segments);
    _lastTranscriptTime = DateTime.now();
    _hasActiveConversation = true;

    // Reset silence timer
    _resetSilenceTimer();

    notifyListeners();
  }

  /// Cloud (Deepgram) results arrive in many small pieces and are merged into
  /// blocks; the local engines keep their own segmentation.
  bool get _mergesSegments {
    final mode = SettingsService.transcriptionMode;
    return mode != 'sherpa' && mode != 'whisper';
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
    // Voice samples gathered for this conversation's speakers (kept so the
    // user can label them later). Taken before the session is reset below.
    final speakerEmbeddings = _speakerId?.session.snapshotEmbeddings();
    final voiceEpoch = _voiceDataEpoch;

    // Start new conversation immediately so listening continues
    _startNewConversation();
    notifyListeners();

    // Generate summary and extract memories with OpenAI (in background)
    if (SettingsService.openaiApiKey.isNotEmpty) {
      _openaiService = OpenAIService(
        apiKey: SettingsService.openaiApiKey,
        model: SettingsService.openaiModel,
      );

      try {
        final result = await _openaiService!.summarizeConversation(
          conversationToSave.transcript,
        );
        conversationToSave.title = result['title'] ?? 'Untitled';
        conversationToSave.summary = result['summary'] ?? '';

        // Save extracted memories (with deduplication)
        final memories = result['memories'] as List<String>? ?? [];
        for (final memoryContent in memories) {
          if (memoryContent.trim().isNotEmpty) {
            final hasSimilar = await DatabaseService.hasSimilarMemory(
              memoryContent,
            );
            if (!hasSimilar) {
              final memory = Memory(
                id: const Uuid().v4(),
                content: memoryContent.trim(),
                category: 'fact',
                createdAt: DateTime.now(),
                sourceConversationId: conversationToSave.id,
              );
              await DatabaseService.saveMemory(memory);
              debugPrint('Saved memory: ${memory.content}');
            } else {
              debugPrint('Skipped duplicate memory: $memoryContent');
            }
          }
        }
        await loadMemories();

        // Save extracted tasks (with deduplication)
        final tasks = result['tasks'] as List? ?? [];
        for (final taskData in tasks) {
          if (taskData is Map && taskData['title'] != null) {
            final title = taskData['title'].toString().trim();
            if (title.isNotEmpty) {
              final hasSimilar = await DatabaseService.hasSimilarTask(title);
              if (!hasSimilar) {
                DateTime? dueDate;
                if (taskData['due_date'] != null) {
                  try {
                    dueDate = DateTime.parse(taskData['due_date'].toString());
                  } catch (e) {
                    debugPrint(
                      'Failed to parse due date: ${taskData['due_date']}',
                    );
                  }
                }
                final task = Task(
                  id: const Uuid().v4(),
                  title: title,
                  description: taskData['description']?.toString(),
                  dueDate: dueDate,
                  createdAt: DateTime.now(),
                  sourceConversationId: conversationToSave.id,
                );
                await DatabaseService.saveTask(task);

                // Schedule notification if due date is set
                if (task.dueDate != null) {
                  await NotificationService().scheduleTaskNotification(
                    id: task.id.hashCode,
                    title: task.title,
                    dueDate: task.dueDate!,
                  );
                }

                debugPrint('Saved task: ${task.title} (due: ${task.dueDate})');
              } else {
                debugPrint('Skipped duplicate task: $title');
              }
            }
          }
        }
        await loadTasks();
      } catch (e) {
        debugPrint('Failed to summarize: $e');
        conversationToSave.title =
            'Conversation ${conversationToSave.createdAt.toString().substring(0, 16)}';
      }
    } else {
      conversationToSave.title =
          'Conversation ${conversationToSave.createdAt.toString().substring(0, 16)}';
    }

    // Save to database
    await DatabaseService.saveConversation(conversationToSave);
    if (speakerEmbeddings != null && speakerEmbeddings.isNotEmpty) {
      await _queueVoiceWrite(() async {
        // "Delete all voice data" ran after these samples were taken: they
        // must not be written back.
        if (voiceEpoch != _voiceDataEpoch) return;
        await DatabaseService.saveConversationSpeakers(
          conversationToSave.id,
          speakerEmbeddings,
        );
      });
    }
    // Expire old voice clips while the app keeps running, not only at start.
    await DatabaseService.purgeOldConversationSpeakers();
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

    // Stop audio source
    if (_isUsingPhoneMic) {
      await _micService.stopRecording();
    } else {
      await _bleService.stopAudioStream();
    }

    // Clean up transcription services
    await _deepgramService?.disconnect();
    _deepgramService = null;
    _speakerId?.dispose();
    _speakerId = null;
    _sherpaService?.stopProcessing();
    _sherpaService?.dispose();
    _sherpaService = null;
    _whisperService?.stopProcessing();
    _whisperService?.dispose();
    _whisperService = null;

    _opusDecoder?.dispose();
    _opusDecoder = null;

    _isListening = false;
    _isUsingPhoneMic = false;
    _currentConversation = null;
    _liveSegments = [];
    notifyListeners();

    debugPrint('Stopped continuous listening');
  }

  // === Speaker Recognition ===
  //
  // Deepgram labels speakers "0, 1, 2 ...". While listening we cut each
  // segment's audio out of a rolling buffer, turn it into a voice embedding
  // with Sherpa-ONNX and compare it with the people the user has labeled
  // before. Labeling a speaker in a saved conversation teaches the app that
  // person's voice (see assignSpeaker).

  List<Person> _people = [];
  List<Person> get people => _people;

  /// True while a speaker-recognition session is attached to the live stream.
  bool get isSpeakerRecognitionActive => _speakerId != null;

  Future<void> _idChain = Future.value();

  /// Completes when the enrolled voices have been loaded into the current
  /// speaker service. Identification waits for it, so the first segments of a
  /// conversation are not matched against an empty list of people.
  Future<void> _profilesLoaded = Future.value();

  /// Bumped each time a conversation ends, so identification work queued for
  /// the old conversation cannot add its clips to the next one.
  int _conversationGen = 0;

  /// Set when the voice model could not be downloaded or loaded, so queued
  /// segments do not each retry the download.
  bool _speakerModelFailed = false;

  Future<void> loadPeople() async {
    _people = await DatabaseService.getPeople();
    _syncSegmentNames();
    await _refreshSpeakerProfiles();
    notifyListeners();
  }

  Future<void> _refreshSpeakerProfiles() async {
    final embeddings = await DatabaseService.getAllPersonEmbeddings();
    final profiles = [
      for (final p in _people)
        SpeakerProfile(
          id: p.id,
          name: p.name,
          embeddings: embeddings[p.id] ?? <Float32List>[],
        ),
    ];
    _speakerId?.setProfiles(profiles);
  }

  /// Make saved transcripts show a person's current name (covers renames).
  void _syncSegmentNames() {
    applyPersonNames(_conversations, {for (final p in _people) p.id: p.name});
  }

  /// Bumped by "Delete all voice data" and when recognition is turned off; a
  /// conversation save that captured its voice samples before that must not
  /// write them afterwards.
  int _voiceDataEpoch = 0;

  /// Voice-sample changes (saving a conversation's samples, labeling a
  /// speaker, delete-all) run one after another, so they cannot interleave.
  final SerialQueue _voiceWrites = SerialQueue();

  Future<T> _queueVoiceWrite<T>(Future<T> Function() op) =>
      _voiceWrites.run(op);

  /// Applies a changed match threshold to the running session.
  void updateSpeakerMatchThreshold(double value) {
    SettingsService.speakerMatchThreshold = value;
    _speakerId?.updateThreshold(value);
  }

  /// Stops recognition in the running session (the setting was turned off):
  /// no more voice samples are computed or kept, and queued work is dropped,
  /// including samples a conversation save captured but has not written yet.
  void stopSpeakerRecognition() {
    _speakerId?.dispose();
    _speakerId = null;
    _speakerStreamGen++;
    _voiceDataEpoch++;
  }

  /// Start speaker recognition for a new Deepgram stream.
  void _startSpeakerId() {
    _speakerId?.dispose();
    _speakerId = null;
    if (!SettingsService.speakerIdEnabled) return;

    final service = SpeakerIdService();
    _speakerId = service;
    _speakerModelFailed = false;
    service.resetStream();
    // A new service starts a new queue, so work still running for the previous
    // service (for example a model download that has not finished) cannot hold
    // it up. That old work drops itself through the stale() checks.
    _idChain = Future.value();
    _profilesLoaded = _refreshSpeakerProfiles().catchError((Object e) {
      debugPrint('Could not load speaker profiles: $e');
    });

    // Download/load the model in the background so transcription starts at once.
    service.initialize().then((_) {
      if (!service.isReady) return; // disposed while loading
      debugPrint('Speaker recognition ready');
      notifyListeners();
    }).catchError((Object e) {
      debugPrint('Speaker recognition unavailable: $e');
    });
  }

  /// Bumped whenever Deepgram's stream clock restarts, when recognition is
  /// turned off, and when all voice data is deleted, so identification work
  /// queued before that can tell it is stale.
  int _speakerStreamGen = 0;

  /// Deepgram dropped the connection and it was re-opened. Its clock and
  /// "speaker N" numbering start over, so restart the speaker timeline too.
  void _onDeepgramReconnected() {
    debugPrint('Deepgram reconnected - restarting the speaker timeline');
    // The new stream numbers its speakers from 0 again, so "speaker 0" before
    // and after can be different people. End the current conversation here so
    // no saved conversation mixes the two numberings (the audio during the
    // drop was lost anyway). This also keeps the voice samples gathered so
    // far, which are read before the reset below.
    if (_currentConversation != null && _liveSegments.isNotEmpty) {
      unawaited(_saveCurrentConversation());
    }
    _speakerStreamGen++;
    _speakerId?.resetStream();
  }

  /// Deepgram stayed unreachable through all the reconnect attempts. Listening
  /// would only throw audio away, so stop (which also saves the conversation
  /// so far) and leave a warning telling the user why.
  void _onDeepgramGaveUp(DeepgramService source) {
    if (!identical(source, _deepgramService)) return; // an old session
    debugPrint('Deepgram unreachable - stopping listening');
    _transcriptionWarning =
        'Lost the connection to Deepgram and could not restore it, so '
        'listening has stopped. Check your internet connection and API key, '
        'then start listening again.';
    notifyListeners();
    // The banner is on the Live tab only, and listening may stop while the app
    // is in the background or another tab is open, so also post a notification.
    NotificationService()
        .showNotification(
          'Omi stopped listening',
          'Could not reach Deepgram. Open the app to start listening again.',
        )
        .catchError((Object e) => debugPrint('Notification failed: $e'));
    unawaited(stopListening());
  }

  /// Send audio to Deepgram and mirror it into the speaker buffer so both share
  /// one timeline. [wireAudio] is what Deepgram expects (Opus or PCM16);
  /// [pcm] is the same audio as PCM16 (null if Opus decoding failed).
  void _sendToDeepgram(Uint8List wireAudio, Uint8List? pcm) {
    final dg = _deepgramService;
    if (dg == null || !dg.isConnected) return; // sendAudio would drop it too
    dg.sendAudio(wireAudio);
    _speakerId?.feedPcm(pcm);
  }

  void _applyKnownSpeakers(List<TranscriptSegment> segments) {
    final svc = _speakerId;
    if (svc == null) return;
    for (final s in segments) {
      final person = svc.session.resolvedFor(s.speakerId);
      if (person != null) {
        s.speakerName = person.name;
        s.personId = person.id;
      }
    }
  }

  void _scheduleSpeakerIdentification(List<TranscriptSegment> segments) {
    final svc = _speakerId;
    if (svc == null) return;
    final gen = _speakerStreamGen;
    final convGen = _conversationGen;
    // One at a time, in order, so embeddings are not computed concurrently.
    _idChain = _idChain
        .then((_) => _identifySegments(svc, segments, gen, convGen))
        .catchError((Object e) {
      debugPrint('Speaker identification error: $e');
    });
  }

  Future<void> _identifySegments(
    SpeakerIdService svc,
    List<TranscriptSegment> segments,
    int gen,
    int convGen,
  ) async {
    // Work queued for an earlier Deepgram stream or conversation is dropped.
    bool stale() =>
        !identical(svc, _speakerId) ||
        gen != _speakerStreamGen ||
        convGen != _conversationGen;
    if (stale() || _speakerModelFailed) return;
    if (!svc.isReady) {
      // First use: the model is still downloading/loading. Wait for it rather
      // than skipping the opening segments of the conversation.
      try {
        await svc.initialize();
      } catch (_) {
        // _startSpeakerId logs the reason.
        if (identical(svc, _speakerId)) _speakerModelFailed = true;
        return;
      }
      if (stale() || !svc.isReady) return;
    }
    await _profilesLoaded;
    if (stale()) return;

    final touched = <int>{};
    for (final seg in segments) {
      final duration = seg.endTime - seg.startTime;
      if (duration < SpeakerIdService.minSegmentSeconds) continue;

      final end = math.min(
        seg.endTime,
        seg.startTime + SpeakerIdService.maxSegmentSeconds,
      );
      final clip = svc.buffer.slice(seg.startTime, end);
      if (clip == null) {
        debugPrint(
          'Speaker clip ${seg.startTime.toStringAsFixed(1)}-${end.toStringAsFixed(1)}s '
          'unavailable (buffer holds ${svc.buffer.durationSeconds.toStringAsFixed(1)}s)',
        );
        continue;
      }

      // Let the UI render between embeddings (the model call is synchronous).
      await Future<void>.delayed(Duration.zero);
      if (stale()) return;

      final embedding = svc.embed(clip);
      if (embedding == null) continue;
      svc.session.addEmbedding(seg.speakerId, embedding);
      touched.add(seg.speakerId);
    }

    var changed = false;
    for (final id in touched) {
      final result = svc.session.resolve(id);
      if (result != null) {
        // Handy when tuning the threshold: watch these lines in the console.
        debugPrint(
          'Speaker $id -> ${result.profile?.name ?? "unknown"} '
          '(score ${result.score.toStringAsFixed(2)}, '
          'runner-up ${result.runnerUp.toStringAsFixed(2)})',
        );
      }
      changed = _applyResolution(id) || changed;
    }
    if (changed) {
      // Naming can reveal that neighboring blocks are the same person.
      if (_mergesSegments) mergeAdjacentSegments(_liveSegments);
      notifyListeners();
    }
  }

  /// Point every live segment of [speakerId] at the currently resolved person.
  bool _applyResolution(int speakerId) {
    final svc = _speakerId;
    if (svc == null) return false;
    final person = svc.session.resolvedFor(speakerId);
    var changed = false;
    for (final seg in _liveSegments) {
      if (seg.speakerId != speakerId || seg.personId == person?.id) continue;
      seg.speakerName = person?.name;
      seg.personId = person?.id;
      changed = true;
    }
    return changed;
  }

  /// Label one speaker of a saved conversation as [personId] (existing) or as
  /// a new person called [newPersonName]. The voice samples captured for that
  /// speaker are enrolled for the person, so they are recognized next time.
  ///
  /// Returns how many voice samples were learned (0 if none were captured, e.g.
  /// speaker recognition was off or the speaker only said short phrases).
  Future<int> assignSpeaker({
    required Conversation conversation,
    required int speakerId,
    String? personId,
    String? newPersonName,
  }) async {
    String id;
    String name;
    if (personId != null) {
      // The person may have been deleted since the sheet was opened.
      final matches = _people.where((p) => p.id == personId);
      if (matches.isEmpty) return 0;
      final person = matches.first;
      id = person.id;
      name = person.name;
    } else {
      name = (newPersonName ?? '').trim();
      if (name.isEmpty) return 0;
      // Reuse an existing person with the same name rather than duplicating.
      final existing = _people.where(
        (p) => p.name.toLowerCase() == name.toLowerCase(),
      );
      if (existing.isNotEmpty) {
        id = existing.first.id;
        name = existing.first.name;
      } else {
        id = const Uuid().v4();
        await DatabaseService.savePerson(id, name);
      }
    }

    // Is this speaker already labeled as the chosen person?
    final speakerSegments =
        conversation.segments.where((s) => s.speakerId == speakerId);
    final alreadyThisPerson =
        speakerSegments.isNotEmpty && speakerSegments.every((s) => s.personId == id);

    // Undo what this speaker previously taught (possibly the wrong person),
    // then enroll their voice samples under the chosen person. One queued
    // step, so a "Delete all voice data" cannot run between reading the
    // samples and writing them.
    final samples = await _queueVoiceWrite<List<Float32List>?>(() async {
      // The person may have been deleted since the sheet was opened.
      final people = await DatabaseService.getPeople();
      if (!people.any((p) => p.id == id)) return null;
      final found = await DatabaseService.getConversationSpeakerEmbeddings(
        conversation.id,
        speakerId,
      );
      // Re-picking the same person after the stored samples were purged: there
      // is nothing to learn again, and removing what this speaker already
      // taught that person would only lose it.
      if (found.isNotEmpty || !alreadyThisPerson) {
        await DatabaseService.removeEnrollmentsFor(conversation.id, speakerId);
      }
      if (found.isNotEmpty) {
        await DatabaseService.addPersonEmbeddings(
          id,
          found,
          conversationId: conversation.id,
          speakerId: speakerId,
        );
      }
      return found;
    });
    if (samples == null) return 0; // person was deleted meanwhile; nothing changed

    for (final seg in conversation.segments) {
      if (seg.speakerId == speakerId) {
        seg.speakerName = name;
        seg.personId = id;
      }
    }
    await DatabaseService.saveConversation(conversation);
    await loadConversations();
    await loadPeople();
    return samples.length;
  }

  /// Remove the name from one speaker of a saved conversation and forget what
  /// their voice samples taught the app.
  Future<void> clearSpeakerLabel({
    required Conversation conversation,
    required int speakerId,
  }) async {
    await _queueVoiceWrite(
      () => DatabaseService.removeEnrollmentsFor(conversation.id, speakerId),
    );
    for (final seg in conversation.segments) {
      if (seg.speakerId == speakerId) {
        seg.speakerName = null;
        seg.personId = null;
      }
    }
    await DatabaseService.saveConversation(conversation);
    await loadConversations();
    await loadPeople();
  }

  /// Renames a person. Returns false (and changes nothing) if the name is
  /// empty or another person already has it.
  Future<bool> renamePerson(String personId, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) return false;
    final lower = name.toLowerCase();
    if (_people.any((p) => p.id != personId && p.name.toLowerCase() == lower)) {
      return false;
    }
    await DatabaseService.renamePerson(personId, name);
    await loadPeople();
    return true;
  }

  /// Deletes a person and their voice samples. Transcripts keep the name text.
  Future<void> deletePerson(String personId) async {
    await _queueVoiceWrite(() => DatabaseService.deletePerson(personId));
    _speakerId?.session.forgetPerson(personId);
    await loadPeople();
  }

  /// Deletes every stored voice sample: those learned for named people (the
  /// people keep their names) and those kept for labeling saved conversations.
  Future<void> deleteAllVoiceData() async {
    _voiceDataEpoch++;
    // Identification work already queued was started on audio from before the
    // delete; it must not add voice samples to the session afterwards.
    _speakerStreamGen++;
    await _queueVoiceWrite(DatabaseService.deleteAllVoiceData);
    for (final p in _people) {
      _speakerId?.session.forgetPerson(p.id);
    }
    _speakerId?.session.startNewConversation();
    await loadPeople();
  }

  // === Conversations Methods ===

  Future<void> loadConversations() async {
    _conversations = await DatabaseService.getConversations();
    _syncSegmentNames();
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
    _chatMessages.add(
      ChatMessage(
        id: const Uuid().v4(),
        text: message,
        isUser: true,
        createdAt: DateTime.now(),
      ),
    );
    _isChatLoading = true;
    notifyListeners();

    // Build context from recent conversations
    final context = _buildMemoryContext();

    // Get AI response
    _openaiService = OpenAIService(
      apiKey: SettingsService.openaiApiKey,
      model: SettingsService.openaiModel,
    );

    try {
      final response = await _openaiService!.chat(
        userMessage: message,
        conversationContext: context,
      );

      _chatMessages.add(
        ChatMessage(
          id: const Uuid().v4(),
          text: response,
          isUser: false,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      _chatMessages.add(
        ChatMessage(
          id: const Uuid().v4(),
          text: 'Error: ${e.toString()}',
          isUser: false,
          createdAt: DateTime.now(),
        ),
      );
    }

    _isChatLoading = false;
    notifyListeners();
  }

  String _buildMemoryContext() {
    final buffer = StringBuffer();

    // Include stored memories first
    if (_memories.isNotEmpty) {
      buffer.writeln('Important facts about the user:');
      for (final memory in _memories.take(20)) {
        buffer.writeln('• ${memory.content}');
      }
      buffer.writeln('');
    }

    // Then add recent conversation summaries
    if (_conversations.isNotEmpty) {
      buffer.writeln('Recent conversation summaries:');
      final recent = _conversations.take(5);
      for (final conv in recent) {
        buffer.writeln('---');
        buffer.writeln('Date: ${conv.createdAt.toString().substring(0, 16)}');
        if (conv.title.isNotEmpty) buffer.writeln('Topic: ${conv.title}');
        if (conv.summary.isNotEmpty) buffer.writeln('Summary: ${conv.summary}');
      }
    }

    return buffer.toString();
  }

  Future<void> loadMemories() async {
    _memories = await DatabaseService.getMemories();
    notifyListeners();
  }

  Future<void> deleteMemory(String id) async {
    await DatabaseService.deleteMemory(id);
    await loadMemories();
  }

  Future<void> updateMemory(String id, String content) async {
    await DatabaseService.updateMemory(id, content);
    await loadMemories();
  }

  Future<void> addMemory(String content, {String? sourceConversationId}) async {
    final memory = Memory(
      id: const Uuid().v4(),
      content: content.trim(),
      category: 'manual',
      createdAt: DateTime.now(),
      sourceConversationId: sourceConversationId,
    );
    await DatabaseService.saveMemory(memory);
    await loadMemories();
  }

  Future<void> loadTasks() async {
    _tasks = await DatabaseService.getTasks();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    // Cancel notification
    await NotificationService().cancelTaskNotification(id.hashCode);

    await DatabaseService.deleteTask(id);
    await loadTasks();
  }

  Future<void> toggleTaskCompletion(String id, bool isCompleted) async {
    await DatabaseService.updateTaskCompletion(id, isCompleted);

    // Manage notification
    if (isCompleted) {
      await NotificationService().cancelTaskNotification(id.hashCode);
    } else {
      // Find task to reschedule if needed
      final taskIndex = _tasks.indexWhere((t) => t.id == id);
      if (taskIndex != -1) {
        final task = _tasks[taskIndex];
        if (task.dueDate != null && task.dueDate!.isAfter(DateTime.now())) {
          await NotificationService().scheduleTaskNotification(
            id: task.id.hashCode,
            title: task.title,
            dueDate: task.dueDate!,
          );
        }
      }
    }

    await loadTasks();
  }

  void clearChat() {
    _chatMessages = [];
    notifyListeners();
  }

  /// Process a local audio file from SD card sync
  /// Returns the transcript text
  Future<String> processLocalAudioFile(String filePath) async {
    debugPrint('Processing local audio file: $filePath');

    // Read the audio data
    final audioData = await SdCardSyncService.readAudioFile(filePath);
    if (audioData == null || audioData.isEmpty) {
      throw Exception('Failed to read audio file');
    }

    debugPrint('Read ${audioData.length} bytes of audio data');

    // Determine codec from filename
    final isOpus = filePath.contains('opus');

    // If Opus, decode to PCM first
    List<int> pcmData;
    if (isOpus) {
      final decoder = OpusDecoderService();
      await decoder.initialize();

      // Decode Opus frames
      pcmData = [];
      int offset = 0;
      while (offset < audioData.length) {
        // Each frame is prefixed with 4-byte length
        if (offset + 4 > audioData.length) break;

        final frameLength =
            audioData[offset] |
            (audioData[offset + 1] << 8) |
            (audioData[offset + 2] << 16) |
            (audioData[offset + 3] << 24);
        offset += 4;

        if (offset + frameLength > audioData.length) break;

        final frame = audioData.sublist(offset, offset + frameLength);
        final decoded = decoder.decode(Uint8List.fromList(frame));
        if (decoded != null) {
          pcmData.addAll(decoded);
        }
        offset += frameLength;
      }

      decoder.dispose();
      debugPrint('Decoded ${pcmData.length} bytes of PCM audio');
    } else {
      pcmData = audioData.toList();
    }

    // Transcribe using the configured transcription method
    final transcriptionMode = SettingsService.transcriptionMode;
    String transcript = '';

    switch (transcriptionMode) {
      case 'whisper':
        debugPrint('Using Whisper for local transcription');
        transcript = await _transcribeWithWhisper(Uint8List.fromList(pcmData));
        break;

      case 'sherpa':
        debugPrint('Using Sherpa for local transcription');
        transcript = await _transcribeWithSherpa(Uint8List.fromList(pcmData));
        break;

      default: // cloud
        debugPrint('Using Deepgram for transcription');
        transcript = await _transcribeWithDeepgram(Uint8List.fromList(pcmData));
    }

    // Save as a conversation if we got a transcript
    if (transcript.isNotEmpty) {
      final conversation = Conversation(
        id: const Uuid().v4(),
        createdAt: DateTime.now(),
        title: 'SD Card Recording',
        segments: [
          TranscriptSegment(
            text: transcript,
            speakerId: 0,
            startTime: 0,
            endTime: 0,
          ),
        ],
      );

      // Try to summarize with OpenAI
      if (SettingsService.openaiApiKey.isNotEmpty) {
        _openaiService = OpenAIService(
          apiKey: SettingsService.openaiApiKey,
          model: SettingsService.openaiModel,
        );

        try {
          final result = await _openaiService!.summarizeConversation(
            transcript,
          );
          conversation.title = result['title'] ?? 'SD Card Recording';
          conversation.summary = result['summary'] ?? '';

          // Extract memories
          final memories = result['memories'] as List<String>? ?? [];
          for (final memoryContent in memories) {
            if (memoryContent.trim().isNotEmpty) {
              final hasSimilar = await DatabaseService.hasSimilarMemory(
                memoryContent,
              );
              if (!hasSimilar) {
                final memory = Memory(
                  id: const Uuid().v4(),
                  content: memoryContent.trim(),
                  category: 'fact',
                  createdAt: DateTime.now(),
                  sourceConversationId: conversation.id,
                );
                await DatabaseService.saveMemory(memory);
              }
            }
          }
          await loadMemories();

          // Extract tasks
          final tasks = result['tasks'] as List? ?? [];
          for (final taskData in tasks) {
            if (taskData is Map && taskData['title'] != null) {
              final title = taskData['title'].toString().trim();
              if (title.isNotEmpty) {
                final hasSimilar = await DatabaseService.hasSimilarTask(title);
                if (!hasSimilar) {
                  DateTime? dueDate;
                  if (taskData['due_date'] != null) {
                    try {
                      dueDate = DateTime.parse(taskData['due_date'].toString());
                    } catch (e) {
                      debugPrint('Failed to parse due date');
                    }
                  }
                  final task = Task(
                    id: const Uuid().v4(),
                    title: title,
                    description: taskData['description']?.toString(),
                    dueDate: dueDate,
                    createdAt: DateTime.now(),
                    sourceConversationId: conversation.id,
                  );
                  await DatabaseService.saveTask(task);
                }
              }
            }
          }
          await loadTasks();
        } catch (e) {
          debugPrint('Failed to summarize SD card recording: $e');
        }
      }

      await DatabaseService.saveConversation(conversation);
      await loadConversations();

      debugPrint(
        'Saved SD card recording as conversation: ${conversation.title}',
      );
    }

    return transcript;
  }

  Future<String> _transcribeWithWhisper(Uint8List pcmData) async {
    final whisper = WhisperService(modelSize: SettingsService.whisperModelSize);

    try {
      await whisper.initialize();

      // Process all audio at once
      whisper.addAudio(pcmData);

      // Wait for processing
      await Future.delayed(const Duration(seconds: 5));

      whisper.stopProcessing();

      // Get accumulated transcript from the service
      // Note: The current WhisperService uses callbacks, so we'd need to modify it
      // For now, return a placeholder
      return 'Transcription with Whisper completed';
    } finally {
      whisper.dispose();
    }
  }

  Future<String> _transcribeWithSherpa(Uint8List pcmData) async {
    final sherpa = SherpaService();

    try {
      await sherpa.initialize();

      // Process all audio
      sherpa.addAudio(pcmData);

      // Wait for processing
      await Future.delayed(const Duration(seconds: 5));

      sherpa.stopProcessing();

      return 'Transcription with Sherpa completed';
    } finally {
      sherpa.dispose();
    }
  }

  Future<String> _transcribeWithDeepgram(Uint8List pcmData) async {
    if (!SettingsService.hasDeepgramKey) {
      throw Exception('Deepgram API key not configured');
    }

    // For file transcription, we'd need to use Deepgram's file upload API
    // instead of the streaming API
    // This is a placeholder - the actual implementation would upload the file

    // Save PCM to temporary WAV file
    final tempDir = await getTemporaryDirectory();
    final wavFile = File(
      '${tempDir.path}/sdcard_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    // Create WAV header
    final header = _buildWavHeader(pcmData.length);
    final wavData = BytesBuilder();
    wavData.add(header);
    wavData.add(pcmData);
    await wavFile.writeAsBytes(wavData.toBytes());

    debugPrint('Saved temporary WAV file: ${wavFile.path}');

    // TODO: Implement Deepgram file upload API
    // For now return placeholder
    return 'Audio file saved. Cloud transcription pending.';
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
      debugPrint(
        'Audio Test Recording finished. Buffer size: ${_testAudioBuffer.length}',
      );
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

  Uint8List _int32ToBytes(int value) =>
      Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  Uint8List _int16ToBytes(int value) =>
      Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);

  Timer?
  _doubleTapTimer; // Keep mainly for debouncing if needed, but logic is now state-driven

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

    // Debounce - prevent multiple button events from being processed too quickly
    if (_isProcessingButtonEvent) {
      debugPrint("Button event blocked - still processing previous event");
      return;
    }
    _isProcessingButtonEvent = true;

    // Parse button state exactly as Omi reference does
    // Little Endian Uint32: [2, 0, 0, 0] -> 2
    final buttonState = ByteData.view(
      Uint8List.fromList(data.sublist(0, 4).reversed.toList()).buffer,
    ).getUint32(0);
    debugPrint("Button State Parsed: $buttonState");

    // STATE 2: Double Tap (End/Save)
    if (buttonState == 2) {
      debugPrint("Double Tap Detected (State 2): Saving Conversation");
      HapticFeedback.heavyImpact(); // Confirm action (Phone)
      _bleService.triggerHaptic(3); // Confirm action (Omi - Long 500ms)
      if (_liveSegments.isEmpty) {
        NotificationService().showNotification(
          "Double Tap",
          "No active conversation to save.",
        );
      } else {
        NotificationService().showNotification(
          "Double Tap",
          "Saving conversation...",
        );
        await manualSaveConversation();
      }
      _isProcessingButtonEvent = false;
      return;
    }

    // STATE 1: Short Press (Toggle - first click starts, second click ends)
    if (buttonState == 1) {
      if (_isHoldToAskActive) {
        // Second click - end AI query and process
        debugPrint("Short Press (State 1): Ending AI Query");
        HapticFeedback.lightImpact(); // Confirm end (Phone)
        _bleService.triggerHaptic(1); // Confirm end (Omi - Short 20ms)

        // Wait to capture trailing audio
        await Future.delayed(const Duration(milliseconds: 1500));

        _isHoldToAskActive = false;
        _isCollectingVoiceCommand = false;
        notifyListeners();

        debugPrint("Final Query Transcript: '$_aiQueryTranscript'");

        _isAiQueryProcessing = true;

        await _processAiQuery();

        _isAiQueryProcessing = false;
        _buttonPressStartTime = null;
        _voiceCommandBuffer = [];
      } else {
        // First click - start AI query
        debugPrint("Short Press (State 1): Starting AI Query");
        HapticFeedback.mediumImpact(); // Confirm start (Phone)
        _bleService.triggerHaptic(2); // Confirm start (Omi - Medium 50ms)
        _buttonPressStartTime = DateTime.now();
        _isHoldToAskActive = true;
        _aiQueryTranscript = '';

        _isCollectingVoiceCommand = true;
        _voiceCommandBuffer = [];

        if (!_isListening) {
          await _bleService.startAudioStream();
          if (_audioSubscription == null) {
            _audioSubscription = _bleService.audioStream.listen(
              _handleOmiAudioData,
            );
          }
          startListening();
        }

        notifyListeners();
      }
      _isProcessingButtonEvent = false;
      return;
    }

    // STATE 4: Short Press End (Not used with toggle - ignore)
    if (buttonState == 4) {
      debugPrint("Short Press End (State 4) - Ignored (using toggle)");
      _isProcessingButtonEvent = false;
      return;
    }

    // STATE 3: Long Press Start (Disabled - now turns off device in new firmware)
    if (buttonState == 3) {
      debugPrint("Long Press Detected (State 3) - Disabled for AI Query");
      _isProcessingButtonEvent = false;
      return;
    }

    // STATE 5: Long Press End
    if (buttonState == 5) {
      debugPrint("Long Press Ended (State 5) - Ignoring (long press disabled)");
      _isProcessingButtonEvent = false;
      return;
    }
  }

  // Audio Data Handler for Omi device (Opus encoded)
  void _handleOmiAudioData(Uint8List audioData) {
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
      // PAUSE: If AI is processing a query, ignore incoming audio for the main conversation
      if (_isAiQueryProcessing) return;

      // Route to active transcription service
      final transcriptionMode = SettingsService.transcriptionMode;
      switch (transcriptionMode) {
        case 'sherpa':
          if (pcmData != null) _sherpaService?.addAudio(pcmData);
          break;
        case 'whisper':
          if (pcmData != null) _whisperService?.addAudio(pcmData);
          break;
        default: // cloud
          // Deepgram expects Opus when encoding='opus'
          _sendToDeepgram(trimmedAudio, pcmData);
      }
    }
  }

  // Audio Data Handler for phone microphone (raw PCM16)
  void _handlePhoneMicAudioData(Uint8List audioData) {
    if (audioData.isEmpty) return;

    // Create a properly aligned copy of the audio data
    // This is needed because Int16List.view requires proper buffer alignment
    final alignedData = Uint8List.fromList(audioData);

    // Route to active transcription service
    final transcriptionMode = SettingsService.transcriptionMode;
    switch (transcriptionMode) {
      case 'sherpa':
        _sherpaService?.addAudio(alignedData);
        break;
      case 'whisper':
        _whisperService?.addAudio(alignedData);
        break;
      default: // cloud
        // Deepgram expects linear16 when encoding='linear16'
        _sendToDeepgram(alignedData, alignedData);
    }
  }

  Future<void> _processAiQuery() async {
    final query = _aiQueryTranscript.trim();
    if (query.isEmpty) {
      NotificationService().showAiResponse(
        "I couldn't hear that. Please try again.",
      );
      return;
    }

    // Notify user we are processing
    if (SettingsService.notifyProcessing) {
      NotificationService().showAiResponse("Processing: $query");
    }

    _openaiService = OpenAIService(
      apiKey: SettingsService.openaiApiKey,
      model: SettingsService.openaiModel,
    );

    try {
      // Chat
      final response = await _openaiService!.chat(
        userMessage: query,
        conversationContext:
            "You are Omi, a helpful AI wearable assistant. Your responses are on notifications, so they MUST be extremely concise. Aim for just the answer. Navigate straight to the point. No fluff.",
      );

      debugPrint('AI Response: $response');
      NotificationService().showAiResponse(response);
    } catch (e) {
      debugPrint("AI Query failed: $e");
      NotificationService().showAiResponse(
        "Failed to process question. Please try again.",
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    debugPrint('App lifecycle state: $state');

    if (state == AppLifecycleState.resumed) {
      NotificationService().resetGlobalBadge();
      // The app can stay alive for days, so check retention on every resume.
      unawaited(DatabaseService.purgeOldConversationSpeakers());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _stateSubscription?.cancel();
    _audioSubscription?.cancel();
    _buttonSubscription?.cancel();
    _silenceTimer?.cancel();
    _bleService.dispose();
    _deepgramService?.disconnect();
    _speakerId?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
