import Foundation

actor AIService {

    // MARK: - Message Types

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let content: String
        let toolCalls: [CoachToolCall]      // assistant tool_use blocks
        let toolResults: [ToolResultBlock]  // user tool_result blocks
        let timestamp = Date()

        enum Role: String { case user, assistant }

        init(role: Role,
             content: String,
             toolCalls: [CoachToolCall] = [],
             toolResults: [ToolResultBlock] = []) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolResults = toolResults
        }

        static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
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
        // --- Legacy, description-matched tools ---
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
        ] as [String: Any],

        // --- ID-based bulk-capable tools ---
        [
            "name": "starTasks",
            "description": "Star one or more tasks, marking them high priority. Starred tasks show a star in the entry list and can be isolated with the Starred filter.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "taskIds": [
                        "type": "array",
                        "items": ["type": "string"] as [String: Any],
                        "description": "Array of task ids (UUIDs) to star"
                    ] as [String: Any]
                ],
                "required": ["taskIds"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "unstarTasks",
            "description": "Unstar one or more tasks, returning them to normal priority. Does not change task status.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "taskIds": [
                        "type": "array",
                        "items": ["type": "string"] as [String: Any]
                    ] as [String: Any]
                ],
                "required": ["taskIds"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "updateDueDate",
            "description": "Set or shift the due date on one or more tasks. Use dueDate for an absolute date, or shift for a relative change.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "taskIds": [
                        "type": "array",
                        "items": ["type": "string"] as [String: Any],
                        "description": "Array of task ids (UUIDs) to update"
                    ] as [String: Any],
                    "dueDate": [
                        "type": "string",
                        "description": "Absolute due date in yyyy-MM-dd format, e.g. 2026-07-31"
                    ] as [String: Any],
                    "shift": [
                        "type": "string",
                        "enum": ["tomorrow", "nextWeek", "clear"],
                        "description": "Relative shift: tomorrow, nextWeek, or clear to remove the due date"
                    ] as [String: Any]
                ],
                "required": ["taskIds"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "updateTaskStatus",
            "description": "Change the status of one or more tasks.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "taskIds": [
                        "type": "array",
                        "items": ["type": "string"] as [String: Any]
                    ] as [String: Any],
                    "status": [
                        "type": "string",
                        "enum": ["to_do", "in_progress", "done"],
                        "description": "New status to apply"
                    ] as [String: Any]
                ],
                "required": ["taskIds", "status"]
            ] as [String: Any]
        ] as [String: Any],
        [
            "name": "bulkUpdate",
            "description": "Apply different changes to different tasks in one call. Use when tasks need different updates simultaneously.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "updates": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "taskId": ["type": "string"] as [String: Any],
                                "star": ["type": "boolean"] as [String: Any],
                                "unstar": ["type": "boolean"] as [String: Any],
                                "dueDate": ["type": "string"] as [String: Any],
                                "shift": [
                                    "type": "string",
                                    "enum": ["tomorrow", "nextWeek", "clear"]
                                ] as [String: Any],
                                "status": [
                                    "type": "string",
                                    "enum": ["to_do", "in_progress", "done"]
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["taskId"]
                        ] as [String: Any]
                    ] as [String: Any]
                ],
                "required": ["updates"]
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

        let human = DateFormatter()
        human.dateFormat = "EEEE, MMMM d, yyyy"
        human.locale = Locale(identifier: "en_US_POSIX")
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        iso.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()

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

        You can make changes to their tasks using tools. When they ask you to start, stop, reschedule, focus, or update tasks, call the appropriate tool rather than just describing what to do.

        Task identification:
        - For start_timer, stop_timer, mark_done, add_time, and set_priority, match task_description to the closest matching task in the data.
        - starTasks, unstarTasks, updateDueDate, updateTaskStatus, and bulkUpdate reference tasks by their "id" (a UUID) from the data. Use bulkUpdate when different tasks need different changes in the same request.

        Starring marks a task high priority. A starred task shows a star in the entry list, and the user can isolate starred work with the Starred filter. Use starTasks / unstarTasks, or the "star" / "unstar" flags in bulkUpdate.

        Status values are "to_do", "in_progress", and "done". For updateDueDate, use shift="tomorrow"/"nextWeek"/"clear" for relative changes, or dueDate (yyyy-MM-dd) for an absolute date.

        Always include a brief text response confirming what you're about to do alongside any tool call — one short sentence like "I'll move those three to tomorrow."
        Today is \(human.string(from: now)) (\(iso.string(from: now))).
        """
    }

    // MARK: - Send

    func send(messages: [Message]) async throws -> CoachResponse {
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
            "max_tokens": 2048,
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
        var toolCalls: [CoachToolCall] = []

        for block in content {
            guard let blockType = block["type"] as? String else { continue }
            if blockType == "text", let t = block["text"] as? String {
                text += t
            } else if blockType == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let rawInput = block["input"] as? [String: Any] {
                toolCalls.append(CoachToolCall(id: id, name: name, input: rawInput))
            }
        }

        return CoachResponse(text: text, toolCalls: toolCalls)
    }

    // MARK: - Build API Messages

    private static func buildAPIMessages(from messages: [Message]) -> [[String: Any]] {
        var apiMessages: [[String: Any]] = []

        for msg in messages {
            if !msg.toolResults.isEmpty {
                // All tool_result blocks for one assistant turn go in a single user message.
                let content = msg.toolResults.map { tr -> [String: Any] in
                    [
                        "type": "tool_result",
                        "tool_use_id": tr.toolUseID,
                        "content": tr.content
                    ]
                }
                apiMessages.append(["role": "user", "content": content])
            } else if !msg.toolCalls.isEmpty {
                var content: [[String: Any]] = []
                if !msg.content.isEmpty {
                    content.append(["type": "text", "text": msg.content])
                }
                for call in msg.toolCalls {
                    content.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": call.input
                    ])
                }
                apiMessages.append(["role": "assistant", "content": content])
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
