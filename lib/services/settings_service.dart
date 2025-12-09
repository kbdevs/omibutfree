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
  
  static bool get useLocalTranscription => transcriptionMode == 'whisper' || transcriptionMode == 'sherpa';
  static bool get useWhisper => transcriptionMode == 'whisper';
  static bool get useSherpa => transcriptionMode == 'sherpa';
  static bool get useDeepgram => transcriptionMode == 'cloud';
  
  // Whisper model selection: tiny, base, small, medium
  static String get whisperModel => prefs.getString('whisper_model') ?? 'base';
  static set whisperModel(String value) => prefs.setString('whisper_model', value);
  
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
}
