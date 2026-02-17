import SwiftUI
import Combine
import AVFoundation
import CoreGraphics

class AppState: ObservableObject {
    @Published var deviceState: DeviceConnectionState = .disconnected
    @Published var batteryLevel: Int?
    @Published var isListening: Bool = false
    @Published var isUsingPhoneMic: Bool = false
    @Published var currentConversation: Conversation?
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var conversations: [Conversation] = []
    @Published var memories: [Memory] = []
    @Published var tasks: [TodoItem] = []
    @Published var isLoadingModel: Bool = false
    @Published var isHoldToAskActive: Bool = false
    @Published var isAiQueryProcessing: Bool = false
    @Published var hasStorageSupport: Bool = false
    @Published var isScanning: Bool = false
    @Published var scannedDevices: [DiscoveredDevice] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var isChatLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isTestingAudio: Bool = false
    
    private var notified50: Bool = false
    private var notified20: Bool = false
    
    let bleService = BLEService()
    let databaseService = DatabaseService.shared
    let settingsService = SettingsService.shared
    let notificationService = NotificationService()
    
    private var deepgramService: DeepgramService?
    private var opusDecoder: OpusDecoderService?
    private var cancellables = Set<AnyCancellable>()
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 120
    
    private var testAudioBuffer: [Int] = []
    private var audioPlayer: AVAudioPlayer?
    
    private var aiQueryTranscript: String = ""
    private var voiceCommandBuffer: [Data] = []
    private var isCollectingVoiceCommand: Bool = false
    
    init() {
        setupBindings()
        Task {
            await initializeApp()
        }
    }
    
    private func initializeApp() async {
        await databaseService.initialize()
        await notificationService.initialize()
        await loadData()
        
        if let savedId = settingsService.savedDeviceId, !savedId.isEmpty {
            _ = await bleService.connectToSavedDevice(savedId)
        }
    }
    
    private func setupBindings() {
        bleService.$deviceState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.deviceState = state
                if state == .connected {
                    Task {
                        await self?.onDeviceConnected()
                    }
                } else if state == .disconnected {
                    if self?.isListening == true && !(self?.isUsingPhoneMic ?? false) {
                        Task {
                            await self?.stopListening()
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        bleService.audioDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleAudioData(data)
            }
            .store(in: &cancellables)
        
        bleService.buttonDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleButtonPress(data)
            }
            .store(in: &cancellables)
    }
    
    private func onDeviceConnected() async {
        batteryLevel = await bleService.getBatteryLevel()
        await checkStorageSupport()
        checkBatteryNotification()
    }
    
    private func checkBatteryNotification() {
        guard let level = batteryLevel else { return }
        
        if level <= 20 && !notified20 {
            notified20 = true
            if settingsService.notifyBatteryCritical {
                notificationService.showNotification(
                    title: "Low Battery Warning",
                    body: "Omi battery is at \(level)%. Please charge soon."
                )
            }
        } else if level <= 50 && !notified50 {
            notified50 = true
            if settingsService.notifyBatteryLow {
                notificationService.showNotification(
                    title: "Battery Getting Low",
                    body: "Omi battery is at \(level)%."
                )
            }
        }
        
        if level > 50 {
            notified50 = false
            notified20 = false
        } else if level > 20 {
            notified20 = false
        }
    }
    
    func loadData() async {
        let conversationsData = await databaseService.getConversations()
        let memoriesData = await databaseService.getMemories()
        let tasksData = await databaseService.getTasks()
        
        await MainActor.run {
            self.conversations = conversationsData
            self.memories = memoriesData
            self.tasks = tasksData
        }
    }
    
    func scanForDevices() {
        Task { @MainActor in
            self.isScanning = true
            self.scannedDevices = []
        }
        
        Task {
            for await devices in bleService.scanForDevices() {
                let omiDevices = devices.filter { $0.name.lowercased().contains("omi") }
                await MainActor.run {
                    if !omiDevices.isEmpty {
                        self.scannedDevices = omiDevices
                    } else if self.scannedDevices.isEmpty {
                        self.scannedDevices = devices
                    }
                }
            }
            await MainActor.run {
                self.isScanning = false
            }
        }
    }
    
    func connectToDevice(_ device: DiscoveredDevice) async -> Bool {
        let success = await bleService.connect(device)
        if success {
            settingsService.savedDeviceId = device.id
            settingsService.savedDeviceName = device.name
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            batteryLevel = await bleService.getBatteryLevel()
            await checkStorageSupport()
        }
        return success
    }
    
    func disconnectDevice() async {
        await stopListening()
        bleService.disconnect()
        await MainActor.run {
            self.batteryLevel = nil
        }
    }
    
    func forgetDevice() async {
        await disconnectDevice()
        settingsService.clearSavedDevice()
    }
    
    private func checkStorageSupport() async {
        let hasStorage = await bleService.hasStorageSupport()
        await MainActor.run {
            self.hasStorageSupport = hasStorage
        }
    }
    
    func startListening() async throws {
        guard deviceState == .connected else {
            throw NSError(domain: "OmiLocal", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Omi device connected"])
        }
        
        guard !isListening else { return }
        
        await MainActor.run {
            self.isUsingPhoneMic = false
        }
        
        opusDecoder = OpusDecoderService()
        await opusDecoder?.initialize()
        
        await bleService.startAudioStream()
        
        await initializeTranscription()
        
        await MainActor.run {
            self.isListening = true
            self.startNewConversation()
        }
    }
    
    func startListeningWithPhoneMic() async throws {
        guard !isListening else { return }
        
        let hasPermission = await MicrophoneService.shared.requestPermission()
        guard hasPermission else {
            throw NSError(domain: "OmiLocal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
        }
        
        await MainActor.run {
            self.isUsingPhoneMic = true
        }
        
        await MicrophoneService.shared.startRecording()
        
        await MicrophoneService.shared.requestPermission()
        
        await initializeTranscription()
        
        await MainActor.run {
            self.isListening = true
            self.startNewConversation()
        }
    }
    
    private func initializeTranscription() async {
        let mode = settingsService.transcriptionMode
        
        switch mode {
        case "cloud":
            guard settingsService.hasDeepgramKey else { return }
            deepgramService = DeepgramService(
                apiKey: settingsService.deepgramApiKey,
                language: settingsService.language
            )
            deepgramService?.onTranscript = { [weak self] segments in
                self?.handleTranscript(segments)
            }
            try? await deepgramService?.connect()
        case "sherpa", "whisper":
            break
        default:
            break
        }
    }
    
    func stopListening() async {
        guard isListening else { return }
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        if hasActiveConversation && !liveSegments.isEmpty {
            await saveCurrentConversation()
        }
        
        if isUsingPhoneMic {
            await MicrophoneService.shared.stopRecording()
        } else {
            await bleService.stopAudioStream()
        }
        
        deepgramService?.disconnect()
        deepgramService = nil
        opusDecoder?.dispose()
        opusDecoder = nil
        
        await MainActor.run {
            self.isListening = false
            self.isUsingPhoneMic = false
            self.currentConversation = nil
            self.liveSegments = []
        }
    }
    
    private func startNewConversation() {
        currentConversation = Conversation(
            id: UUID().uuidString,
            createdAt: Date()
        )
        liveSegments = []
    }
    
    private func handleAudioData(_ data: Data) {
        guard isListening else { return }
        
        if !isUsingPhoneMic {
            let trimmedData = data.count > 3 ? data.subdata(in: data.startIndex.advanced(by: 3)..<data.endIndex) : data
            
            if isCollectingVoiceCommand {
                voiceCommandBuffer.append(trimmedData)
            }
            
            if isTestingAudio, let decoded = opusDecoder?.decode(trimmedData) {
                for sample in decoded {
                    testAudioBuffer.append(Int(sample))
                }
            }
            
            if isAiQueryProcessing { return }
            
            if let decoded = opusDecoder?.decode(trimmedData) {
                if settingsService.transcriptionMode == "cloud" {
                    deepgramService?.sendAudio(decoded)
                }
            } else {
                if settingsService.transcriptionMode == "cloud" {
                    deepgramService?.sendAudio(trimmedData)
                }
            }
        } else {
            if isAiQueryProcessing { return }
            
            if settingsService.transcriptionMode == "cloud" {
                deepgramService?.sendAudio(data)
            }
        }
    }
    
    private func handleTranscript(_ segments: [TranscriptSegment]) {
        guard isListening else { return }
        
        for segment in segments {
            if isHoldToAskActive && !segment.text.isEmpty {
                aiQueryTranscript += " \(segment.text)"
            }
        }
        
        liveSegments.append(contentsOf: segments)
        resetSilenceTimer()
        objectWillChange.send()
    }
    
    private func handleButtonPress(_ data: [UInt8]) {
        guard data.count >= 4 else { return }
        
        let buttonState = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        
        switch buttonState {
        case 1:
            if isHoldToAskActive {
                endAiQuery()
            } else {
                startAiQuery()
            }
        case 2:
            if !liveSegments.isEmpty {
                Task {
                    await saveCurrentConversation()
                }
            }
        default:
            break
        }
    }
    
    private func startAiQuery() {
        isHoldToAskActive = true
        aiQueryTranscript = ""
        isCollectingVoiceCommand = true
        
        if !isListening {
            Task {
                try? await startListening()
            }
        }
    }
    
    private func endAiQuery() {
        isHoldToAskActive = false
        isCollectingVoiceCommand = false
        isAiQueryProcessing = true
        
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await processAiQuery()
            isAiQueryProcessing = false
        }
    }
    
    var hasActiveConversation: Bool {
        !liveSegments.isEmpty
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.hasActiveConversation else { return }
            Task {
                await self.saveCurrentConversation()
            }
        }
    }
    
    private func saveCurrentConversation() async {
        guard let conversationToSave = currentConversation, !liveSegments.isEmpty else {
            startNewConversation()
            return
        }
        
        var conversation = conversationToSave
        conversation.segments = liveSegments
        startNewConversation()
        
        if !settingsService.openaiApiKey.isEmpty {
            let openaiService = OpenAIService(apiKey: settingsService.openaiApiKey, model: settingsService.openaiModel)
            do {
                let result = try await openaiService.summarizeConversation(conversation.transcript)
                conversation.title = result.title
                conversation.summary = result.summary
                
                for memoryContent in result.memories {
                    let hasSimilar = await databaseService.hasSimilarMemory(memoryContent)
                    if !hasSimilar {
                        let memory = Memory(
                            id: UUID().uuidString,
                            content: memoryContent,
                            category: "fact",
                            createdAt: Date(),
                            sourceConversationId: conversation.id
                        )
                        await databaseService.saveMemory(memory)
                    }
                }
                
                for taskData in result.tasks {
                    let hasSimilar = await databaseService.hasSimilarTask(taskData.title)
                    if !hasSimilar {
                        let task = TodoItem(
                            id: UUID().uuidString,
                            title: taskData.title,
                            description: taskData.description,
                            dueDate: taskData.dueDate,
                            createdAt: Date(),
                            sourceConversationId: conversation.id
                        )
                        await databaseService.saveTask(task)
                        
                        if let dueDate = task.dueDate {
                            await notificationService.scheduleTaskNotification(id: task.id.hashValue, title: task.title, dueDate: dueDate)
                        }
                    }
                }
            } catch {
                conversation.title = "Conversation \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))"
            }
        } else {
            conversation.title = "Conversation \(conversation.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
        
        await databaseService.saveConversation(conversation)
        
        if SettingsService.shared.notifyProcessing {
            notificationService.showNotification(
                title: "Conversation Saved",
                body: conversation.title.isEmpty ? "New conversation saved" : conversation.title
            )
        }
        
        await loadData()
    }
    
    func manualSaveConversation() async {
        guard !liveSegments.isEmpty else { return }
        await saveCurrentConversation()
    }
    
    func deleteConversation(_ id: String) async {
        await databaseService.deleteConversation(id)
        await loadData()
    }
    
    func deleteMemory(_ id: String) async {
        await databaseService.deleteMemory(id)
        await loadData()
    }
    
    func updateMemory(_ id: String, content: String) async {
        await databaseService.updateMemory(id, newContent: content)
        await loadData()
    }
    
    func deleteTask(_ id: String) async {
        await notificationService.cancelTaskNotification(id.hashValue)
        await databaseService.deleteTask(id)
        await loadData()
    }
    
    func toggleTaskCompletion(_ id: String, isCompleted: Bool) async {
        await databaseService.updateTaskCompletion(taskId: id, completed: isCompleted)
        
        if isCompleted {
            await notificationService.cancelTaskNotification(id.hashValue)
        }
        
        await loadData()
    }
    
    func addMemory(_ content: String, sourceConversationId: String? = nil) async {
        let memory = Memory(
            id: UUID().uuidString,
            content: content,
            category: "manual",
            createdAt: Date(),
            sourceConversationId: sourceConversationId
        )
        await databaseService.saveMemory(memory)
        await loadData()
    }
    
    func sendChatMessage(_ message: String) async {
        guard !message.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard settingsService.hasOpenAIKey else {
            errorMessage = "Please configure OpenAI API key in settings"
            return
        }
        
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            text: message,
            isUser: true,
            createdAt: Date()
        )
        chatMessages.append(userMessage)
        isChatLoading = true
        
        let openaiService = OpenAIService(apiKey: settingsService.openaiApiKey, model: settingsService.openaiModel)
        
        do {
            let context = buildMemoryContext()
            let response = try await openaiService.chat(userMessage: message, conversationContext: context)
            
            let aiMessage = ChatMessage(
                id: UUID().uuidString,
                text: response,
                isUser: false,
                createdAt: Date()
            )
            chatMessages.append(aiMessage)
        } catch {
            let errorMsg = ChatMessage(
                id: UUID().uuidString,
                text: "Error: \(error.localizedDescription)",
                isUser: false,
                createdAt: Date()
            )
            chatMessages.append(errorMsg)
        }
        
        isChatLoading = false
    }
    
    private func buildMemoryContext() -> String {
        var buffer = ""
        
        if !memories.isEmpty {
            buffer += "Important facts about the user:\n"
            for memory in memories.prefix(20) {
                buffer += "• \(memory.content)\n"
            }
            buffer += "\n"
        }
        
        if !conversations.isEmpty {
            buffer += "Recent conversation summaries:\n"
            for conv in conversations.prefix(5) {
                buffer += "---\n"
                buffer += "Date: \(conv.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
                if !conv.title.isEmpty {
                    buffer += "Topic: \(conv.title)\n"
                }
                if !conv.summary.isEmpty {
                    buffer += "Summary: \(conv.summary)\n"
                }
            }
        }
        
        return buffer
    }
    
    func clearChat() {
        chatMessages = []
    }
    
    // MARK: - Audio Test
    
    func startAudioTest() async {
        guard !isTestingAudio else { return }
        
        if !isListening {
            if let savedId = settingsService.savedDeviceId, !savedId.isEmpty {
                _ = await bleService.connectToSavedDevice(savedId)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if deviceState == .connected {
                try? await startListening()
            } else {
                return
            }
        }
        
        await MainActor.run {
            self.isTestingAudio = true
            self.testAudioBuffer = []
        }
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        
        await MainActor.run {
            self.isTestingAudio = false
        }
        
        if !testAudioBuffer.isEmpty {
            await playBackTestAudio()
        }
    }
    
    private func playBackTestAudio() async {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("test_audio.wav")
        
        let wavData = buildWavHeader(dataSize: testAudioBuffer.count * 2)
        
        var audioData = Data()
        for sample in testAudioBuffer {
            let int16Sample = Int16(clamping: sample)
            audioData.append(Data(bytes: [int16Sample], count: 2))
        }
        
        var fullData = wavData
        fullData.append(audioData)
        
        do {
            try fullData.write(to: tempFile)
            audioPlayer = try AVAudioPlayer(contentsOf: tempFile)
            audioPlayer?.play()
        } catch {
            print("Audio playback error: \(error)")
        }
    }
    
    private func buildWavHeader(dataSize: Int) -> Data {
        var header = Data()
        
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let fileSize = UInt32(dataSize) + 36
        
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        
        return header
    }
    
    // MARK: - Hold-to-Ask AI
    
    private func processAiQuery() async {
        let query = aiQueryTranscript.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            notificationService.showNotification(
                title: "Omi AI",
                body: "I couldn't hear that. Please try again."
            )
            return
        }
        
        if settingsService.notifyProcessing {
            notificationService.showNotification(
                title: "Processing",
                body: query
            )
        }
        
        let openaiService = OpenAIService(apiKey: settingsService.openaiApiKey, model: settingsService.openaiModel)
        
        do {
            let response = try await openaiService.chat(
                userMessage: query,
                conversationContext: "You are Omi, a helpful AI wearable assistant. Your responses are on notifications, so they MUST be extremely concise. Aim for just the answer. Navigate straight to the point. No fluff."
            )
            
            notificationService.showNotification(title: "Omi AI", body: response)
        } catch {
            notificationService.showNotification(
                title: "Omi AI",
                body: "Failed to process question. Please try again."
            )
        }
        
        aiQueryTranscript = ""
    }
}
