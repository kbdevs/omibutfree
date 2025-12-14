/// Settings service for storing API keys locally
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    if (_prefs == null) {
      throw Exception('SettingsService not initialized. Call init() first.');
    }
    return _prefs!;
  }

  // API Keys
  static String get deepgramApiKey => prefs.getString('deepgram_api_key') ?? '';
  static set deepgramApiKey(String value) => prefs.setString('deepgram_api_key', value);

  static String get openaiApiKey => prefs.getString('openai_api_key') ?? '';
  static set openaiApiKey(String value) => prefs.setString('openai_api_key', value);

  // Settings
  static String get language => prefs.getString('language') ?? 'en';
  static set language(String value) => prefs.setString('language', value);

  static String get openaiModel => prefs.getString('openai_model') ?? 'gpt-5-nano';
  static set openaiModel(String value) => prefs.setString('openai_model', value);
  
  // Transcription mode: 'cloud' (Deepgram), 'whisper', or 'sherpa'
  static String get transcriptionMode => prefs.getString('transcription_mode') ?? 'cloud';
  static set transcriptionMode(String value) => prefs.setString('transcription_mode', value);
  
  // Whisper model size: 'tiny' or 'base'
  static String get whisperModelSize => prefs.getString('whisper_model_size') ?? 'tiny';
  static set whisperModelSize(String value) => prefs.setString('whisper_model_size', value);
  
  static bool get useLocalTranscription => transcriptionMode == 'sherpa' || transcriptionMode == 'whisper';
  static bool get useSherpa => transcriptionMode == 'sherpa';
  static bool get useWhisper => transcriptionMode == 'whisper';
  static bool get useDeepgram => transcriptionMode == 'cloud';
  
  // Audio source: 'omi' (default) or 'phone_mic'
  static String get audioSource => prefs.getString('audio_source') ?? 'omi';
  static set audioSource(String value) => prefs.setString('audio_source', value);
  
  static bool get useOmiDevice => audioSource == 'omi';
  static bool get usePhoneMic => audioSource == 'phone_mic';

  
  // Saved device for auto-connect
  static String get savedDeviceId => prefs.getString('saved_device_id') ?? '';
  static set savedDeviceId(String value) => prefs.setString('saved_device_id', value);
  
  static String get savedDeviceName => prefs.getString('saved_device_name') ?? '';
  static set savedDeviceName(String value) => prefs.setString('saved_device_name', value);
  
  static void clearSavedDevice() {
    prefs.remove('saved_device_id');
    prefs.remove('saved_device_name');
  }

  // Helper
  static bool get hasApiKeys => (deepgramApiKey.isNotEmpty || useLocalTranscription) && openaiApiKey.isNotEmpty;
  static bool get hasOpenAIKey => openaiApiKey.isNotEmpty;
  static bool get hasDeepgramKey => deepgramApiKey.isNotEmpty;
  
  // Notification settings
  static bool get notifyBatteryLow => prefs.getBool('notify_battery_low') ?? true;
  static set notifyBatteryLow(bool value) => prefs.setBool('notify_battery_low', value);
  
  static bool get notifyBatteryCritical => prefs.getBool('notify_battery_critical') ?? true;
  static set notifyBatteryCritical(bool value) => prefs.setBool('notify_battery_critical', value);
  
  static bool get notifyTaskReminders => prefs.getBool('notify_task_reminders') ?? true;
  static set notifyTaskReminders(bool value) => prefs.setBool('notify_task_reminders', value);
  
  static bool get notifyProcessing => prefs.getBool('notify_processing') ?? true;
  static set notifyProcessing(bool value) => prefs.setBool('notify_processing', value);
  
  // iCloud backup
  static bool get icloudBackupEnabled => prefs.getBool('icloud_backup_enabled') ?? false;
  static set icloudBackupEnabled(bool value) => prefs.setBool('icloud_backup_enabled', value);
  
  // API Usage Tracking
  static double get deepgramMinutesUsed => prefs.getDouble('deepgram_minutes_used') ?? 0.0;
  static set deepgramMinutesUsed(double value) => prefs.setDouble('deepgram_minutes_used', value);
  
  static int get openaiInputTokens => prefs.getInt('openai_input_tokens') ?? 0;
  static set openaiInputTokens(int value) => prefs.setInt('openai_input_tokens', value);
  
  static int get openaiOutputTokens => prefs.getInt('openai_output_tokens') ?? 0;
  static set openaiOutputTokens(int value) => prefs.setInt('openai_output_tokens', value);
  
  // Track usage
  static void addDeepgramUsage(double minutes) {
    deepgramMinutesUsed = deepgramMinutesUsed + minutes;
  }
  
  static void addOpenAIUsage(int inputTokens, int outputTokens) {
    openaiInputTokens = openaiInputTokens + inputTokens;
    openaiOutputTokens = openaiOutputTokens + outputTokens;
  }
  
  static void resetUsageStats() {
    deepgramMinutesUsed = 0.0;
    openaiInputTokens = 0;
    openaiOutputTokens = 0;
  }
  
  // Pricing (per 1M tokens for OpenAI, per minute for Deepgram)
  static const Map<String, Map<String, double>> openaiPricing = {
    'gpt-5-nano': {'input': 0.10, 'output': 0.40},
    'gpt-5-mini': {'input': 0.40, 'output': 1.60},
    'gpt-5': {'input': 2.00, 'output': 8.00},
    'gpt-4o-mini': {'input': 0.15, 'output': 0.60},
    'gpt-4o': {'input': 2.50, 'output': 10.00},
    'gpt-4.1': {'input': 2.00, 'output': 8.00},
    'gpt-4.1-mini': {'input': 0.40, 'output': 1.60},
    'gpt-4.1-nano': {'input': 0.10, 'output': 0.40},
    'gpt-4-turbo': {'input': 10.00, 'output': 30.00},
    'gpt-3.5-turbo': {'input': 0.50, 'output': 1.50},
  };
  
  static const double deepgramPricePerMinute = 0.0059; // Nova-2 streaming
  
  // Cost calculations
  static double get deepgramCost => deepgramMinutesUsed * deepgramPricePerMinute;
  
  static double get openaiCost {
    final model = openaiModel;
    final pricing = openaiPricing[model] ?? {'input': 2.00, 'output': 8.00}; // Default to gpt-4.1 pricing
    final inputCost = (openaiInputTokens / 1000000) * pricing['input']!;
    final outputCost = (openaiOutputTokens / 1000000) * pricing['output']!;
    return inputCost + outputCost;
  }
  
  static double get totalApiCost => deepgramCost + openaiCost;
}
