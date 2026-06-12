import Foundation

actor AIService {

    // MARK: - Message Types

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        let toolUse: ToolUseRequest?
        let toolResultID: String?
        let timestamp = Date()

        enum Role: String { case user, assistant }

        init(role: Role, content: String, toolUse: ToolUseRequest? = nil, toolResultID: String? = nil) {
            self.role = role
            self.content = content
            self.toolUse = toolUse
            self.toolResultID = toolResultID
        }

        static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
    }

    struct ToolUseRequest: Equatable {
        let id: String
        let name: String
        let input: [String: String]

        var displayDescription: String {
            switch name {
            case "start_timer":
                return "Start timer on \"\(input["task_description"] ?? "unknown")\""
            case "stop_timer":
                return "Stop timer on \"\(input["task_description"] ?? "unknown")\""
            case "mark_done":
                return "Mark \"\(input["task_description"] ?? "unknown")\" as done"
            case "add_time":
                let mins = input["minutes"] ?? "?"
                return "Add \(mins) min to \"\(input["task_description"] ?? "unknown")\""
            case "set_priority":
                let level = input["priority"] ?? "?"
                return "Set \"\(input["task_description"] ?? "unknown")\" priority to \(level)"
            default:
                return "\(name)"
            }
        }
    }

    // MARK: - API Key

    private static let apiKeyKey = "ai.anthropicAPIKey"

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    static var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Tool Definitions

    static let tools: [[String: Any]] = [
        [
            "name": "start_timer",
            "description": "Start the timer on a task. Use the task_description to identify which task.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_description": [
                        "type": "string",
                        "description": "The description or service name of the task to start"
                    ]
                ],
                "required": ["task_description"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "stop_timer",
            "description": "Stop/pause the currently running timer on a task and log the elapsed time.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_description": [
                        "type": "string",
                        "description": "The description or service name of the task to stop"
                    ]
                ],
                "required": ["task_description"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "mark_done",
            "description": "Mark a task as completed.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_description": [
                        "type": "string",
                        "description": "The description or service name of the task to complete"
                    ]
                ],
                "required": ["task_description"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "add_time",
            "description": "Add logged time to a task without starting a timer.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_description": [
                        "type": "string",
                        "description": "The description or service name of the task"
                    ],
                    "minutes": [
                        "type": "string",
                        "description": "Number of minutes to add"
                    ]
                ],
                "required": ["task_description", "minutes"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "set_priority",
            "description": "Set a task as high priority (starred) or normal priority.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_description": [
                        "type": "string",
                        "description": "The description or service name of the task"
                    ],
                    "priority": [
                        "type": "string",
                        "enum": ["high", "normal"],
                        "description": "Priority level"
                    ]
                ],
                "required": ["task_description", "priority"]
            ] as [String: Any]
        ] as [String: Any]
    ]

    // MARK: - System Prompt

    private let systemPrompt: String

    init(taskJSON: String, userName: String = "", companyName: String = "") {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = companyName.trimmingCharacters(in: .whitespacesAndNewlines)

        let userDescription: String
        switch (name.isEmpty, company.isEmpty) {
        case (true, true): userDescription = "a freelancer"
        case (true, false): userDescription = "a freelancer who runs \(company)"
        case (false, true): userDescription = "\(name), a freelancer"
        case (false, false): userDescription = "\(name), a freelancer who runs \(company)"
        }
        let userRef = name.isEmpty ? "the user" : name

        self.systemPrompt = """
        You are a work coach and productivity assistant for \(userDescription). You help them stay organized, prioritize tasks, and keep track of time across multiple clients.
        Here is their current task and time data:
        \(taskJSON)
        When helping \(userRef):
        - Prioritize based on what's overdue, stalled, or time-sensitive
        - Group suggestions by client or task type when it makes sense
        - Flag anything that looks like it's been sitting too long without activity
        - Keep responses concise — they're usually checking in quickly between tasks
        - If they ask what to work on, give them a short, confident recommendation — not a long list
        - When they ask you to do something (start a timer, mark done, add time, etc.), use the appropriate tool
        - When using a tool, match the task_description to the closest matching task in the data
        - Always include a brief text response along with any tool use
        """
    }

    // MARK: - Send

    func send(messages: [Message]) async throws -> AIResponse {
        let key = Self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.noAPIKey }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let apiMessages = Self.buildAPIMessages(from: messages)

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": systemPrompt,
            "tools": Self.tools,
            "messages": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse
        }

        if http.statusCode == 401 { throw AIError.invalidKey }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(status: http.statusCode, body: body)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AIError.parseError
        }

        var text = ""
        var toolUse: ToolUseRequest?

        for block in content {
            if let blockType = block["type"] as? String {
                if blockType == "text", let t = block["text"] as? String {
                    text = t
                } else if blockType == "tool_use",
                          let id = block["id"] as? String,
                          let name = block["name"] as? String,
                          let rawInput = block["input"] as? [String: Any] {
                    let stringInput = rawInput.mapValues { "\($0)" }
                    toolUse = ToolUseRequest(id: id, name: name, input: stringInput)
                }
            }
        }

        return AIResponse(text: text, toolUse: toolUse)
    }

    struct AIResponse {
        let text: String
        let toolUse: ToolUseRequest?
    }

    // MARK: - Build API Messages

    private static func buildAPIMessages(from messages: [Message]) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            if let toolResultID = msg.toolResultID {
                apiMessages.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": toolResultID,
                            "content": msg.content
                        ] as [String: Any]
                    ]
                ])
            } else if let toolUse = msg.toolUse {
                var content: [[String: Any]] = []
                if !msg.content.isEmpty {
                    content.append(["type": "text", "text": msg.content])
                }
                content.append([
                    "type": "tool_use",
                    "id": toolUse.id,
                    "name": toolUse.name,
                    "input": toolUse.input
                ])
                apiMessages.append([
                    "role": "assistant",
                    "content": content
                ])
            } else {
                apiMessages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }
        }

        return apiMessages
    }

    // MARK: - Errors

    enum AIError: LocalizedError {
        case noAPIKey
        case invalidKey
        case badResponse
        case parseError
        case apiError(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "Add your Anthropic API key in Settings to use the AI coach."
            case .invalidKey: return "Invalid API key. Check your key in Settings."
            case .badResponse: return "Unexpected response from the server."
            case .parseError: return "Could not parse the AI response."
            case .apiError(let status, let body): return "API error (HTTP \(status)): \(body)"
            }
        }
    }
}
