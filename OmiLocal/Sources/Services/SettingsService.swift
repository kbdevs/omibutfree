import Foundation

class SettingsService {
    static let shared = SettingsService()
    
    private let defaults = UserDefaults.standard
    
    init() {}
    
    var deepgramApiKey: String {
        get { defaults.string(forKey: "deepgram_api_key") ?? "" }
        set { defaults.set(newValue, forKey: "deepgram_api_key") }
    }
    
    var openaiApiKey: String {
        get { defaults.string(forKey: "openai_api_key") ?? "" }
        set { defaults.set(newValue, forKey: "openai_api_key") }
    }
    
    var language: String {
        get { defaults.string(forKey: "language") ?? "en" }
        set { defaults.set(newValue, forKey: "language") }
    }
    
    var openaiModel: String {
        get { defaults.string(forKey: "openai_model") ?? "gpt-4.1-mini" }
        set { defaults.set(newValue, forKey: "openai_model") }
    }
    
    var transcriptionMode: String {
        get { defaults.string(forKey: "transcription_mode") ?? "cloud" }
        set { defaults.set(newValue, forKey: "transcription_mode") }
    }
    
    var whisperModelSize: String {
        get { defaults.string(forKey: "whisper_model_size") ?? "tiny" }
        set { defaults.set(newValue, forKey: "whisper_model_size") }
    }
    
    var audioSource: String {
        get { defaults.string(forKey: "audio_source") ?? "omi" }
        set { defaults.set(newValue, forKey: "audio_source") }
    }
    
    var savedDeviceId: String? {
        get { defaults.string(forKey: "saved_device_id") }
        set { defaults.set(newValue, forKey: "saved_device_id") }
    }
    
    var savedDeviceName: String? {
        get { defaults.string(forKey: "saved_device_name") }
        set { defaults.set(newValue, forKey: "saved_device_name") }
    }
    
    var hasApiKeys: Bool {
        (!deepgramApiKey.isEmpty || transcriptionMode == "sherpa" || transcriptionMode == "whisper") && !openaiApiKey.isEmpty
    }
    
    var hasOpenAIKey: Bool {
        !openaiApiKey.isEmpty
    }
    
    var hasDeepgramKey: Bool {
        !deepgramApiKey.isEmpty
    }
    
    var notifyBatteryLow: Bool {
        get { defaults.bool(forKey: "notify_battery_low") }
        set { defaults.set(newValue, forKey: "notify_battery_low") }
    }
    
    var notifyBatteryCritical: Bool {
        get { defaults.bool(forKey: "notify_battery_critical") }
        set { defaults.set(newValue, forKey: "notify_battery_critical") }
    }
    
    var notifyTaskReminders: Bool {
        get { defaults.bool(forKey: "notify_task_reminders") }
        set { defaults.set(newValue, forKey: "notify_task_reminders") }
    }
    
    var notifyProcessing: Bool {
        get { defaults.object(forKey: "notify_processing") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notify_processing") }
    }
    
    var deepgramMinutesUsed: Double {
        get { defaults.double(forKey: "deepgram_minutes_used") }
        set { defaults.set(newValue, forKey: "deepgram_minutes_used") }
    }
    
    var openaiInputTokens: Int {
        get { defaults.integer(forKey: "openai_input_tokens") }
        set { defaults.set(newValue, forKey: "openai_input_tokens") }
    }
    
    var openaiOutputTokens: Int {
        get { defaults.integer(forKey: "openai_output_tokens") }
        set { defaults.set(newValue, forKey: "openai_output_tokens") }
    }
    
    func addDeepgramUsage(_ minutes: Double) {
        deepgramMinutesUsed += minutes
    }
    
    func addOpenAIUsage(input: Int, output: Int) {
        openaiInputTokens += input
        openaiOutputTokens += output
    }
    
    func resetUsageStats() {
        deepgramMinutesUsed = 0
        openaiInputTokens = 0
        openaiOutputTokens = 0
    }
    
    func clearSavedDevice() {
        defaults.removeObject(forKey: "saved_device_id")
        defaults.removeObject(forKey: "saved_device_name")
    }
}
