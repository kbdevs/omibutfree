import Foundation

class OpenAIService {
    let apiKey: String
    let model: String
    
    init(apiKey: String, model: String = "gpt-4.1-mini") {
        self.apiKey = apiKey
        self.model = model
    }
    
    func chat(userMessage: String, conversationContext: String?) async throws -> String {
        var messages: [[String: String]] = []
        
        var systemPrompt = "You are a helpful AI assistant. You have access to the user's conversation history and memories."
        
        if let context = conversationContext, !context.isEmpty {
            systemPrompt += """
            
            Here is the user's recent conversation history for context:
            
            \(context)
            
            Use this context to provide personalized and relevant responses.
            """
        }
        
        messages.append(["role": "system", "content": systemPrompt])
        messages.append(["role": "user", "content": userMessage])
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": 1000
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])
        }
        
        if let usage = json["usage"] as? [String: Any] {
            let inputTokens = usage["prompt_tokens"] as? Int ?? 0
            let outputTokens = usage["completion_tokens"] as? Int ?? 0
            SettingsService.shared.addOpenAIUsage(input: inputTokens, output: outputTokens)
        }
        
        return content
    }
    
    func summarizeConversation(_ transcript: String, currentTime: Date = Date()) async throws -> SummaryResult {
        let dateFormatter = ISO8601DateFormatter()
        let timeContext = "Current date/time: \(dateFormatter.string(from: currentTime))"
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let systemPrompt = """
        You analyze conversations and extract key information.
        \(timeContext)
        
        Respond with JSON only:
        {
          "title": "short descriptive title",
          "summary": "brief 1-2 sentence summary",
          "memories": ["important fact 1", "important fact 2"],
          "tasks": [
            {"title": "task description", "due_date": "2024-12-12T18:00:00"}
          ]
        }
        
        For memories, extract ONLY important facts worth remembering long-term, such as:
        - Names (e.g., "User's name is Karsten")
        - Preferences (e.g., "User prefers tea over coffee")
        - Personal details (e.g., "User works as a software engineer")
        
        For tasks, extract actionable items mentioned.
        
        If there are no notable facts/tasks, return empty arrays.
        """
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": "Analyze this conversation:\n\n\(transcript)"]
            ],
            "max_tokens": 700,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return SummaryResult(title: "Untitled Conversation", summary: "", memories: [], tasks: [])
        }
        
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else {
            return SummaryResult(title: "Untitled Conversation", summary: "", memories: [], tasks: [])
        }
        
        let title = parsed["title"] as? String ?? "Untitled Conversation"
        let summary = parsed["summary"] as? String ?? ""
        let memories = parsed["memories"] as? [String] ?? []
        
        var tasks: [TaskData] = []
        if let taskArray = parsed["tasks"] as? [[String: Any]] {
            for taskDict in taskArray {
                let taskTitle = taskDict["title"] as? String ?? ""
                let taskDescription = taskDict["description"] as? String
                var dueDate: Date?
                if let dueDateStr = taskDict["due_date"] as? String {
                    dueDate = dateFormatter.date(from: dueDateStr)
                }
                tasks.append(TaskData(title: taskTitle, description: taskDescription, dueDate: dueDate))
            }
        }
        
        return SummaryResult(title: title, summary: summary, memories: memories, tasks: tasks)
    }
}
