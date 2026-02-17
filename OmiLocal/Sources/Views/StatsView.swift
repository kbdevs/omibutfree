import SwiftUI

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Your Omi Stats")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Insights from your conversations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            
            Section {
                HStack {
                    StatCard(
                        icon: "chatbubble",
                        label: "Conversations",
                        value: "\(appState.conversations.count)",
                        color: .purple
                    )
                    StatCard(
                        icon: "brain",
                        label: "Memories",
                        value: "\(appState.memories.count)",
                        color: .green
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                
                HStack {
                    StatCard(
                        icon: "checkmark.circle",
                        label: "Tasks",
                        value: "\(completedTasks)/\(appState.tasks.count)",
                        color: .yellow
                    )
                    StatCard(
                        icon: "clock",
                        label: "This Week",
                        value: "\(recentConversations)",
                        color: .blue
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            
            Section("Totals") {
                HStack {
                    Label("Words Captured", systemImage: "textformat")
                    Spacer()
                    Text("\(totalWords)")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Recording Time", systemImage: "timer")
                    Spacer()
                    Text(formatDuration(totalDuration))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("First Conversation", systemImage: "calendar")
                    Spacer()
                    Text(firstConversationDate)
                        .foregroundColor(.secondary)
                }
            }
            
            if !appState.memories.isEmpty {
                Section("Memory Sources") {
                    HStack {
                        Label("Auto-extracted", systemImage: "wand.and.stars")
                        Spacer()
                        Text("\(autoExtractedMemories)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Manually Added", systemImage: "pencil")
                        Spacer()
                        Text("\(manualMemories)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section("API Costs (Estimated)") {
                HStack {
                    Label("Deepgram", systemImage: "waveform")
                    Spacer()
                    Text(String(format: "$%.4f", deepgramCost))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("OpenAI", systemImage: "cpu")
                    Spacer()
                    Text(String(format: "$%.4f", openaiCost))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Label("Total Estimated", systemImage: "dollarsign.circle")
                    Spacer()
                    Text(String(format: "$%.4f", totalCost))
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
            }
            
            Section {
                Button(role: .destructive) {
                    SettingsService.shared.resetUsageStats()
                } label: {
                    Label("Reset All Statistics", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Statistics")
    }
    
    private var completedTasks: Int {
        appState.tasks.filter { $0.isCompleted }.count
    }
    
    private var recentConversations: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return appState.conversations.filter { $0.createdAt > weekAgo }.count
    }
    
    private var totalWords: Int {
        appState.conversations.reduce(0) { total, conv in
            total + conv.segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        }
    }
    
    private var totalDuration: TimeInterval {
        appState.conversations.reduce(0) { $0 + $1.duration }
    }
    
    private var firstConversationDate: String {
        guard let first = appState.conversations.last else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: first.createdAt)
    }
    
    private var autoExtractedMemories: Int {
        appState.memories.filter { $0.category != "manual" }.count
    }
    
    private var manualMemories: Int {
        appState.memories.filter { $0.category == "manual" }.count
    }
    
    private var deepgramCost: Double {
        SettingsService.shared.deepgramMinutesUsed * 0.0059
    }
    
    private var openaiCost: Double {
        let inputTokens = SettingsService.shared.openaiInputTokens
        let outputTokens = SettingsService.shared.openaiOutputTokens
        let model = SettingsService.shared.openaiModel
        
        let pricing: (input: Double, output: Double)
        switch model {
        case "gpt-4.1": pricing = (2.00, 8.00)
        case "gpt-4.1-mini": pricing = (0.40, 1.60)
        case "gpt-4.1-nano": pricing = (0.10, 0.40)
        case "gpt-4o": pricing = (2.50, 10.00)
        case "gpt-4o-mini": pricing = (0.15, 0.60)
        default: pricing = (0.50, 1.50)
        }
        
        let inputCost = (Double(inputTokens) / 1_000_000) * pricing.input
        let outputCost = (Double(outputTokens) / 1_000_000) * pricing.output
        return inputCost + outputCost
    }
    
    private var totalCost: Double {
        deepgramCost + openaiCost
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}

struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
