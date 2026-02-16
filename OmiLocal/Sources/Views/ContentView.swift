import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            if appState.isHoldToAskActive {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // End AI query
                    }
                
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.purple.opacity(0.5), radius: 20, x: 0, y: 0)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                    
                    Text("Listening...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Click again to finish")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            TabView(selection: $selectedTab) {
                DeviceTabView()
                    .tabItem {
                        Label("Live", systemImage: selectedTab == 0 ? "mic.fill" : "mic")
                    }
                    .tag(0)
                
                ConversationsView()
                    .tabItem {
                        Label("History", systemImage: selectedTab == 1 ? "history.fill" : "history")
                    }
                    .tag(1)
                
                MemoriesView()
                    .tabItem {
                        Label("Memories", systemImage: selectedTab == 2 ? "brain.fill" : "brain")
                    }
                    .tag(2)
                
                TasksView()
                    .tabItem {
                        Label("Tasks", systemImage: selectedTab == 3 ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .tag(3)
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: selectedTab == 4 ? "gearshape.fill" : "gearshape")
                    }
                    .tag(4)
            }
            .tint(Color.purple)
        }
    }
}

struct DeviceTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var isScanning = false
    
    var body: some View {
        NavigationStack {
            List {
                if appState.isListening || appState.isUsingPhoneMic {
                    ListeningSection()
                } else {
                    DisconnectedSection(isScanning: $isScanning)
                }
            }
            .navigationTitle("Omi Local")
            .toolbar {
                if let batteryLevel = appState.batteryLevel {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 4) {
                            Image(systemName: batteryLevel > 20 ? "battery.100" : "battery.25")
                                .foregroundColor(batteryLevel > 20 ? .green : .red)
                            Text("\(batteryLevel)%")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}

struct DisconnectedSection: View {
    @EnvironmentObject var appState: AppState
    @Binding var isScanning: Bool
    
    var body: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.purple)
                
                Text("Start Capturing")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose your audio source to capture and transcribe conversations.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            
            if !SettingsService.shared.hasApiKeys {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Missing API Keys")
                        .fontWeight(.bold)
                    Spacer()
                    Button("Settings") {
                        // Navigate to settings
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            
            Button(action: {
                appState.scanForDevices()
                isScanning = true
            }) {
                HStack {
                    Image(systemName: "wave.3.right")
                    Text("Use Omi Device")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                Task {
                    try? await appState.startListeningWithPhoneMic()
                }
            }) {
                HStack {
                    Image(systemName: "iphone")
                    Text("Use iPhone Microphone")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!SettingsService.shared.hasApiKeys)
            
            if isScanning && appState.isScanning {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Scanning for devices...")
                }
            }
            
            ForEach(appState.scannedDevices) { device in
                HStack {
                    Image(systemName: "wave.3.right")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .fontWeight(.medium)
                        Text(device.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Connect") {
                        Task {
                            _ = await appState.connectToDevice(device)
                            isScanning = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
        }
    }
}

struct ListeningSection: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("Listening...")
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
                
                Text("Saves automatically after 2 min silence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            
            Button(action: {
                Task {
                    await appState.stopListening()
                }
            }) {
                Text("Stop Listening")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            if !appState.liveSegments.isEmpty {
                Button(action: {
                    Task {
                        await appState.manualSaveConversation()
                    }
                }) {
                    Text("Save Now")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        
        if !appState.liveSegments.isEmpty {
            Section("Current Conversation") {
                ForEach(appState.liveSegments) { segment in
                    HStack(alignment: .top) {
                        Text("S\(segment.speakerId)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        
                        Text(segment.text)
                    }
                }
            }
        }
    }
}

struct ConversationsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    
    var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return appState.conversations
        }
        return appState.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.conversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "history")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)
                        Text("No conversations yet")
                            .font(.title3)
                        Text("Start recording to create your first conversation")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(filteredConversations) { conversation in
                        NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                                    .fontWeight(.medium)
                                
                                if !conversation.summary.isEmpty {
                                    Text(conversation.summary)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                
                                HStack {
                                    Text(formatDate(conversation.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    if conversation.duration > 0 {
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text(formatDuration(conversation.duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search conversations")
                }
            }
            .navigationTitle("Conversations")
            .refreshable {
                // Reload conversations
            }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct ConversationDetailView: View {
    let conversation: Conversation
    @EnvironmentObject var appState: AppState
    @State private var showDeleteAlert = false
    
    var body: some View {
        List {
            Section("Summary") {
                if conversation.summary.isEmpty {
                    Text("No summary available")
                        .foregroundColor(.secondary)
                } else {
                    Text(conversation.summary)
                }
            }
            
            Section("Transcript") {
                ForEach(conversation.segments) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Speaker \(segment.speakerId)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            Spacer()
                        }
                        Text(segment.text)
                    }
                }
            }
        }
        .navigationTitle(conversation.title.isEmpty ? "Conversation" : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .alert("Delete Conversation", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await appState.deleteConversation(conversation.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete this conversation?")
        }
    }
}

struct MemoriesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showAddMemory = false
    @State private var newMemoryText = ""
    
    var filteredMemories: [Memory] {
        if searchText.isEmpty {
            return appState.memories
        }
        return appState.memories.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.memories.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "brain")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)
                        Text("No memories yet")
                            .font(.title3)
                        Text("Memories will be extracted from your conversations")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(filteredMemories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.content)
                            Text(formatDate(memory.createdAt))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search memories")
                }
            }
            .navigationTitle("Memories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Add Memory", isPresented: $showAddMemory) {
                TextField("Memory content", text: $newMemoryText)
                Button("Cancel", role: .cancel) {
                    newMemoryText = ""
                }
                Button("Add") {
                    Task {
                        await appState.addMemory(newMemoryText)
                        newMemoryText = ""
                    }
                }
            }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    
    var incompleteTasks: [TodoItem] {
        appState.tasks.filter { !$0.isCompleted }
    }
    
    var completedTasks: [TodoItem] {
        appState.tasks.filter { $0.isCompleted }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.tasks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.gray)
                        Text("No tasks yet")
                            .font(.title3)
                        Text("Tasks will be extracted from your conversations")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        if !incompleteTasks.isEmpty {
                            Section("To Do") {
                                ForEach(incompleteTasks) { task in
                                    TaskRow(task: task)
                                }
                            }
                        }
                        
                        if !completedTasks.isEmpty {
                            Section("Completed") {
                                ForEach(completedTasks) { task in
                                    TaskRow(task: task)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tasks")
        }
    }
}

struct TaskRow: View {
    let task: TodoItem
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack {
            Button {
                Task {
                    await appState.toggleTaskCompletion(task.id, isCompleted: !task.isCompleted)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                if let dueDate = task.dueDate {
                    Text(formatDueDate(dueDate))
                        .font(.caption)
                        .foregroundColor(dueDate < Date() ? .red : .secondary)
                }
            }
        }
    }
    
    func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Due: \(formatter.string(from: date))"
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var deepgramKey = SettingsService.shared.deepgramApiKey
    @State private var openaiKey = SettingsService.shared.openaiApiKey
    @State private var showDeepgramKey = false
    @State private var showOpenAIKey = false
    @State private var transcriptionMode = SettingsService.shared.transcriptionMode
    @State private var selectedModel = SettingsService.shared.openaiModel
    
    var body: some View {
        NavigationStack {
            List {
                Section("Connected Device") {
                    if let savedName = SettingsService.shared.savedDeviceName {
                        HStack {
                            Image(systemName: "wave.3.right")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text(savedName)
                                    .fontWeight(.medium)
                                Text(appState.deviceState == .connected ? "Connected" : "Saved Device")
                                    .font(.caption)
                                    .foregroundColor(appState.deviceState == .connected ? .green : .secondary)
                            }
                            Spacer()
                            if appState.deviceState == .connected {
                                Button("Disconnect") {
                                    Task {
                                        await appState.disconnectDevice()
                                    }
                                }
                            } else {
                                Button("Connect") {
                                    Task {
                                        if let deviceId = SettingsService.shared.savedDeviceId {
                                            _ = await appState.connectToDevice(DiscoveredDevice(id: deviceId, name: savedName, rssi: 0))
                                        }
                                    }
                                }
                            }
                        }
                        
                        Button("Forget Device") {
                            Task {
                                await appState.forgetDevice()
                            }
                        }
                        .foregroundColor(.red)
                    } else {
                        Text("No device saved")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("API Keys") {
                    HStack {
                        Text("Deepgram")
                        Spacer()
                        SecureField("API Key", text: $deepgramKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .onChange(of: deepgramKey) { newValue in
                                SettingsService.shared.deepgramApiKey = newValue
                            }
                    }
                    
                    HStack {
                        Text("OpenAI")
                        Spacer()
                        SecureField("API Key", text: $openaiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .onChange(of: openaiKey) { newValue in
                                SettingsService.shared.openaiApiKey = newValue
                            }
                    }
                }
                
                Section("Transcription Engine") {
                    Picker("Mode", selection: $transcriptionMode) {
                        Text("Cloud (Deepgram)").tag("cloud")
                        Text("Local (Sherpa)").tag("sherpa")
                        Text("Local (Whisper)").tag("whisper")
                    }
                    .onChange(of: transcriptionMode) { newValue in
                        SettingsService.shared.transcriptionMode = newValue
                    }
                }
                
                Section("OpenAI Model") {
                    Picker("Model", selection: $selectedModel) {
                        Text("GPT-4.1 Mini").tag("gpt-4.1-mini")
                        Text("GPT-4o Mini").tag("gpt-4o-mini")
                        Text("GPT-4o").tag("gpt-4o")
                        Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                    }
                    .onChange(of: selectedModel) { newValue in
                        SettingsService.shared.openaiModel = newValue
                    }
                }
                
                Section("Usage Stats") {
                    HStack {
                        Text("Deepgram Minutes")
                        Spacer()
                        Text(String(format: "%.2f", SettingsService.shared.deepgramMinutesUsed))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("OpenAI Input Tokens")
                        Spacer()
                        Text("\(SettingsService.shared.openaiInputTokens)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("OpenAI Output Tokens")
                        Spacer()
                        Text("\(SettingsService.shared.openaiOutputTokens)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
