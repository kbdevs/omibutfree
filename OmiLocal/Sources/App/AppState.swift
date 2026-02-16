import SwiftUI
import Combine

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
    
    let bleService = BLEService()
    let databaseService = DatabaseService()
    let settingsService = SettingsService()
    let notificationService = NotificationService()
    
    private var cancellables = Set<AnyCancellable>()
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 120
    
    init() {
        setupBindings()
        Task {
            await loadData()
        }
    }
    
    private func setupBindings() {
        bleService.$deviceState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.deviceState = state
                if state == .connected {
                    self?.batteryLevel = self?.bleService.batteryLevel
                    Task {
                        await self?.checkStorageSupport()
                    }
                } else if state == .disconnected {
                    self?.batteryLevel = nil
                    if self?.isListening == true && !(self?.isUsingPhoneMic ?? false) {
                        Task {
                            await self?.stopListening()
                        }
                    }
                }
            }
            .store(in: &cancellables)
        
        bleService.$audioData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleAudioData(data)
            }
            .store(in: &cancellables)
        
        bleService.$buttonData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.handleButtonPress(data)
            }
            .store(in: &cancellables)
    }
    
    private func loadData() async {
        await databaseService.initialize()
        conversations = await databaseService.getConversations()
        memories = await databaseService.getMemories()
        tasks = await databaseService.getTasks()
        
        if let savedId = settingsService.savedDeviceId, !savedId.isEmpty {
            _ = await bleService.connectToSavedDevice(savedId)
        }
    }
    
    func scanForDevices() {
        isScanning = true
        scannedDevices = []
        Task {
            for await devices in bleService.scanForDevices() {
                await MainActor.run {
                    self.scannedDevices = devices
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
            batteryLevel = bleService.batteryLevel
            await checkStorageSupport()
        }
        return success
    }
    
    func disconnectDevice() async {
        await stopListening()
        bleService.disconnect()
        batteryLevel = nil
    }
    
    func forgetDevice() async {
        await disconnectDevice()
        settingsService.clearSavedDevice()
    }
    
    private func checkStorageSupport() async {
        hasStorageSupport = await bleService.hasStorageSupport()
    }
    
    func startListening() async throws {
        guard deviceState == .connected else {
            throw NSError(domain: "OmiLocal", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Omi device connected"])
        }
        
        guard !isListening else { return }
        
        isUsingPhoneMic = false
        await bleService.startAudioStream()
        
        isListening = true
        startNewConversation()
    }
    
    func startListeningWithPhoneMic() async throws {
        guard !isListening else { return }
        
        isUsingPhoneMic = true
        await MicrophoneService.shared.startRecording()
        
        isListening = true
        startNewConversation()
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
        
        isListening = false
        isUsingPhoneMic = false
        currentConversation = nil
        liveSegments = []
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
        
        // Process audio through transcription service
        // This would connect to Deepgram or local transcription
    }
    
    private func handleButtonPress(_ data: [UInt8]) {
        guard data.count >= 4 else { return }
        
        let buttonState = UInt32(data[0]) | (UInt32(data[1]) << 8) | (UInt32(data[2]) << 16) | (UInt32(data[3]) << 24)
        
        switch buttonState {
        case 1: // Short Press Start
            if isHoldToAskActive {
                endAiQuery()
            } else {
                startAiQuery()
            }
        case 2: // Double Tap - Save
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
    }
    
    private func endAiQuery() {
        isHoldToAskActive = false
        // Process AI query
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
    
    func addTranscriptSegment(_ segment: TranscriptSegment) {
        liveSegments.append(segment)
        resetSilenceTimer()
        objectWillChange.send()
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
    
    func deleteTask(_ id: String) async {
        await notificationService.cancelTaskNotification(id.hashValue)
        await databaseService.deleteTask(id)
        await loadData()
    }
    
    func toggleTaskCompletion(_ id: String, isCompleted: Bool) async {
        await databaseService.updateTaskCompletion(id: id, isCompleted: isCompleted)
        
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
}
