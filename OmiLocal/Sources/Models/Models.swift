import Foundation

enum DeviceConnectionState {
    case disconnected
    case connecting
    case connected
}

struct TranscriptSegment: Identifiable, Codable {
    let id = UUID()
    var text: String
    var speakerId: Int
    var startTime: Double
    var endTime: Double
    var isUser: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case text, speakerId = "speaker_id", startTime = "start", endTime = "end", isUser = "is_user"
    }
}

struct Conversation: Identifiable, Codable {
    var id: String
    let createdAt: Date
    var title: String = ""
    var summary: String = ""
    var segments: [TranscriptSegment] = []
    
    var transcript: String {
        segments.map { "Speaker \($0.speakerId): \($0.text)" }.joined(separator: "\n")
    }
    
    var duration: TimeInterval {
        guard let first = segments.first, let last = segments.last else { return 0 }
        return last.endTime - first.startTime
    }
    
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else if totalSeconds < 3600 {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
    }
}

struct Memory: Identifiable, Codable {
    let id: String
    var content: String
    var category: String
    let createdAt: Date
    var sourceConversationId: String?
}

struct TodoItem: Identifiable, Codable {
    let id: String
    var title: String
    var description: String?
    var dueDate: Date?
    let createdAt: Date
    var sourceConversationId: String?
    var isCompleted: Bool = false
}

struct ChatMessage: Identifiable, Codable {
    let id: String
    var text: String
    var isUser: Bool
    let createdAt: Date
}

struct DiscoveredDevice: Identifiable {
    let id: String
    let name: String
    let rssi: Int
}

struct SummaryResult {
    var title: String
    var summary: String
    var memories: [String]
    var tasks: [TaskData]
}

struct TaskData {
    var title: String
    var description: String?
    var dueDate: Date?
}
