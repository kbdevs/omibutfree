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

  static String get openaiModel => prefs.getString('openai_model') ?? 'gpt-4o-mini';
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
}
