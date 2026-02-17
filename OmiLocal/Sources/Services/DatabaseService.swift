import Foundation
import SQLite

class DatabaseService {
    static let shared = DatabaseService()
    
    private var db: Connection?
    
    private let conversations = Table("conversations")
    private let memories = Table("memories")
    private let tasks = Table("tasks")
    
    private let id = SQLite.Expression<String>("id")
    private let createdAt = SQLite.Expression<Int64>("created_at")
    private let title = SQLite.Expression<String?>("title")
    private let summary = SQLite.Expression<String?>("summary")
    private let transcript = SQLite.Expression<String?>("transcript")
    private let content = SQLite.Expression<String>("content")
    private let category = SQLite.Expression<String>("category")
    private let sourceConversationId = SQLite.Expression<String?>("source_conversation_id")
    private let descriptionCol = SQLite.Expression<String?>("description")
    private let dueDate = SQLite.Expression<Int64?>("due_date")
    private let isCompleted = SQLite.Expression<Int64>("is_completed")
    
    init() {}
    
    func initialize() async {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsURL.appendingPathComponent("omi_local.db").path
        
        do {
            db = try Connection(dbPath)
            
            try db?.run(conversations.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(createdAt)
                t.column(title)
                t.column(summary)
                t.column(transcript)
            })
            
            try db?.run(memories.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(content)
                t.column(category)
                t.column(createdAt)
                t.column(sourceConversationId)
            })
            
            try db?.run(tasks.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(title)
                t.column(descriptionCol)
                t.column(dueDate)
                t.column(createdAt)
                t.column(sourceConversationId)
                t.column(isCompleted, defaultValue: 0)
            })
            
            print("Database initialized at: \(dbPath)")
        } catch {
            print("Database initialization failed: \(error)")
        }
    }
    
    func saveConversation(_ conversation: Conversation) async {
        guard let db = db else { return }
        
        let transcriptJson = try? JSONEncoder().encode(conversation.segments)
        let transcriptStr = transcriptJson.flatMap { String(data: $0, encoding: .utf8) }
        
        do {
            let insert = conversations.insert(or: .replace,
                id <- conversation.id,
                createdAt <- Int64(conversation.createdAt.timeIntervalSince1970),
                title <- conversation.title,
                summary <- conversation.summary,
                transcript <- transcriptStr
            )
            try db.run(insert)
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
    
    func getConversations(limit: Int = 50) async -> [Conversation] {
        guard let db = db else { return [] }
        
        var result: [Conversation] = []
        
        do {
            for row in try db.prepare(conversations.order(createdAt.desc).limit(limit)) {
                var segments: [TranscriptSegment] = []
                if let transcriptStr = row[transcript],
                   let data = transcriptStr.data(using: .utf8) {
                    segments = (try? JSONDecoder().decode([TranscriptSegment].self, from: data)) ?? []
                }
                
                let conversation = Conversation(
                    id: row[id],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                    title: row[title] ?? "",
                    summary: row[summary] ?? "",
                    segments: segments
                )
                result.append(conversation)
            }
        } catch {
            print("Failed to get conversations: \(error)")
        }
        
        return result
    }
    
    func deleteConversation(_ convId: String) async {
        guard let db = db else { return }
        
        do {
            let conversation = conversations.filter(id == convId)
            try db.run(conversation.delete())
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }
    
    func saveMemory(_ memory: Memory) async {
        guard let db = db else { return }
        
        do {
            let insert = memories.insert(or: .replace,
                id <- memory.id,
                content <- memory.content,
                category <- memory.category,
                createdAt <- Int64(memory.createdAt.timeIntervalSince1970),
                sourceConversationId <- memory.sourceConversationId
            )
            try db.run(insert)
        } catch {
            print("Failed to save memory: \(error)")
        }
    }
    
    func getMemories(limit: Int = 100) async -> [Memory] {
        guard let db = db else { return [] }
        
        var result: [Memory] = []
        
        do {
            for row in try db.prepare(memories.order(createdAt.desc).limit(limit)) {
                let memory = Memory(
                    id: row[id],
                    content: row[content],
                    category: row[category],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                    sourceConversationId: row[sourceConversationId]
                )
                result.append(memory)
            }
        } catch {
            print("Failed to get memories: \(error)")
        }
        
        return result
    }
    
    func deleteMemory(_ memId: String) async {
        guard let db = db else { return }
        
        do {
            let memory = memories.filter(id == memId)
            try db.run(memory.delete())
        } catch {
            print("Failed to delete memory: \(error)")
        }
    }
    
    func hasSimilarMemory(_ memContent: String) async -> Bool {
        guard let db = db else { return false }
        
        do {
            let query = memories.filter(content.like("%\(memContent)%"))
            return try db.scalar(query.count) > 0
        } catch {
            return false
        }
    }
    
    func updateMemory(_ memId: String, newContent: String) async {
        guard let db = db else { return }
        
        do {
            let memory = memories.filter(id == memId)
            try db.run(memory.update(content <- newContent))
        } catch {
            print("Failed to update memory: \(error)")
        }
    }
    
    func saveTask(_ task: TodoItem) async {
        guard let db = db else { return }
        
        do {
            let insert = tasks.insert(or: .replace,
                id <- task.id,
                title <- task.title,
                descriptionCol <- task.description,
                dueDate <- task.dueDate.map { Int64($0.timeIntervalSince1970) },
                createdAt <- Int64(task.createdAt.timeIntervalSince1970),
                sourceConversationId <- task.sourceConversationId,
                isCompleted <- task.isCompleted ? 1 : 0
            )
            try db.run(insert)
        } catch {
            print("Failed to save task: \(error)")
        }
    }
    
    func getTasks(limit: Int = 100) async -> [TodoItem] {
        guard let db = db else { return [] }
        
        var result: [TodoItem] = []
        
        do {
            for row in try db.prepare(tasks.order(createdAt.desc).limit(limit)) {
                let task = TodoItem(
                    id: row[id],
                    title: row[title] ?? "",
                    description: row[descriptionCol],
                    dueDate: row[dueDate].map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row[createdAt])),
                    sourceConversationId: row[sourceConversationId],
                    isCompleted: row[isCompleted] == 1
                )
                result.append(task)
            }
        } catch {
            print("Failed to get tasks: \(error)")
        }
        
        return result
    }
    
    func deleteTask(_ taskId: String) async {
        guard let db = db else { return }
        
        do {
            let task = tasks.filter(id == taskId)
            try db.run(task.delete())
        } catch {
            print("Failed to delete task: \(error)")
        }
    }
    
    func updateTaskCompletion(taskId: String, completed: Bool) async {
        guard let db = db else { return }
        
        do {
            let task = tasks.filter(id == taskId)
            try db.run(task.update(isCompleted <- (completed ? 1 : 0)))
        } catch {
            print("Failed to update task: \(error)")
        }
    }
    
    func hasSimilarTask(_ taskTitle: String) async -> Bool {
        guard let db = db else { return false }
        
        do {
            let query = tasks.filter(title.like("%\(taskTitle)%"))
            return try db.scalar(query.count) > 0
        } catch {
            return false
        }
    }
    
    func exportAllData() async -> [String: Any] {
        let convs = await getConversations(limit: 1000)
        let mems = await getMemories(limit: 1000)
        let tks = await getTasks(limit: 1000)
        
        return [
            "conversations": convs.map { conv in
                [
                    "id": conv.id,
                    "created_at": conv.createdAt.timeIntervalSince1970,
                    "title": conv.title,
                    "summary": conv.summary,
                    "segments": conv.segments.map { $0.toDictionary() }
                ]
            },
            "memories": mems.map { mem in
                [
                    "id": mem.id,
                    "content": mem.content,
                    "category": mem.category,
                    "created_at": mem.createdAt.timeIntervalSince1970,
                    "source_conversation_id": mem.sourceConversationId ?? ""
                ]
            },
            "tasks": tks.map { tk in
                [
                    "id": tk.id,
                    "title": tk.title,
                    "description": tk.description ?? "",
                    "due_date": tk.dueDate?.timeIntervalSince1970 ?? 0,
                    "created_at": tk.createdAt.timeIntervalSince1970,
                    "is_completed": tk.isCompleted
                ]
            },
            "exported_at": Date().timeIntervalSince1970
        ]
    }
}

extension TranscriptSegment {
    func toDictionary() -> [String: Any] {
        return [
            "text": text,
            "speaker_id": speakerId,
            "start": startTime,
            "end": endTime,
            "is_user": isUser
        ]
    }
}
