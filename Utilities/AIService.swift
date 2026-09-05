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

    /// Sonnet is the floor for the Coach: it runs a multi-step loop, and Haiku
    /// was picking the wrong task out of thirty clients often enough to matter.
    static let model = "claude-sonnet-5"

    /// Safety net on the agentic loop — a model that keeps calling tools without
    /// converging stops here rather than billing forever.
    static let maxLoopTurns = 8

    private static let apiKeyKey = "ai.anthropicAPIKey"

    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyKey) }
    }

    static var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Tool Definitions

    /// Defined in `CoachToolSchema` so the schema sits next to the executor and
    /// the confirmation policy rather than buried in the networking layer.
    static let tools: [[String: Any]] = CoachToolSchema.all

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

        let possessive = name.isEmpty ? "the user's" : name + "'s"
        let whoTheyAre = userDescription.isEmpty
            ? "a freelancer"
            : userDescription.prefix(1).uppercased() + String(userDescription.dropFirst())

        self.systemPrompt = """
        You are Claude, working as a coach inside \(possessive) time-tracking app. \(whoTheyAre) is who you're helping. You keep them organized, help them prioritize, and track time across clients.

        You are not a narrow assistant. You have your full knowledge and judgement
        here, and questions do not have to be about tasks to be worth answering —
        answer whatever they ask, as you would anywhere else. Never tell them a
        question is outside what you help with, and never deflect and then answer
        anyway in parentheses; that is worse than either. The app is where this
        conversation happens, not the limit of it.

        What is specific to here is that you can see and change their work. Lead
        with that when the question touches it, and otherwise just be useful.

        Here is their current task and time data:
        \(taskJSON)
        When helping \(userRef):
        - Prioritize based on what's overdue, stalled, or time-sensitive
        - Group suggestions by client or task type when it makes sense
        - Flag anything that looks like it's been sitting too long without activity
        - Keep responses concise — they're usually checking in quickly between tasks
        - If they ask what to work on, give them a short, confident recommendation — not a long list

        The data above is OPEN WORK ONLY — completed tasks, invoiced work and past
        time logs are not in it. Never answer a question about finished or billed
        work from that snapshot; use findTasks with status "done" or "any", or
        getClientSummary, and say what you actually found.

        You act through tools, and you can chain them: call a tool, read the
        result, then decide the next step.

        Finish the whole request before you reply. "Log two hours, add an editing
        subtask, and tick it off" is three separate changes, and you are not done
        until each one has come back with a tool result. A tool you did not call
        did not happen. Never describe a change you have not seen succeed — if
        you have logged the time but not yet added the subtask, do not say you
        added the subtask. Before your final message, check the user's request
        item by item against the results you actually received, and say plainly
        if something is still outstanding.

        Task identification:
        - Every write tool takes a task id. Ids for open tasks are in the data above.
        - If the user names a task in words and you cannot see it above, call
          findTasks first. Never invent an id and never guess between two similar
          tasks — if findTasks returns more than one plausible match, ask which.
        - Use bulkUpdate only when several tasks need DIFFERENT changes at once.

        New tasks: if \(userRef) hasn't said what state it's in, don't pass a
        status — createTask then files it as a Quick Capture, which is where
        unreviewed notes belong and where they're easy to find. Pass a status only
        when they actually gave one.

        Logging work: addTime takes minutes, so two hours is 120. Pass date
        (yyyy-MM-dd) when the work happened on an earlier day. addSubtask with
        done=true records something already finished.

        Starring marks a task high priority; it shows a star in the entry list and
        the user can isolate starred work with the Starred filter.

        Status values are "to_do", "in_progress" and "done". For updateDueDate use
        shift="tomorrow"/"nextWeek"/"clear", or dueDate (yyyy-MM-dd).

        Some changes are applied the moment you call them; wider ones are shown to
        \(userRef) for approval first. Either way, say in one short sentence what
        you are doing — "Logging 2h and ticking off the editing subtask." Do not
        claim a change succeeded before you have seen its tool result.
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
        request.timeoutInterval = 90

        let apiMessages = Self.buildAPIMessages(from: messages)

        // The tool schemas and the system prompt — task payload included — come to
        // roughly 9k tokens, and the agentic loop re-sends every byte of it on
        // each turn. A single top-level breakpoint caches the tools/system/history
        // prefix and moves forward as the conversation grows, so turns after the
        // first read at $0.20/MTok instead of $2. Roughly a 60% saving on a
        // multi-step exchange, and it degrades to normal pricing on a miss.
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 4096,
            "cache_control": ["type": "ephemeral"],
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

        #if DEBUG
        if let usage = json["usage"] as? [String: Any] {
            let fresh = usage["input_tokens"] as? Int ?? 0
            let written = usage["cache_creation_input_tokens"] as? Int ?? 0
            let read = usage["cache_read_input_tokens"] as? Int ?? 0
            let out = usage["output_tokens"] as? Int ?? 0
            // Sonnet 5: $2/MTok in, $10 out, $2.50 cache write, $0.20 cache read.
            let cents = (Double(fresh) * 2 + Double(written) * 2.5
                         + Double(read) * 0.2 + Double(out) * 10) / 10_000
            print(String(format: "[Coach] tokens in=%d cached_write=%d cached_read=%d out=%d — %.3f¢",
                         fresh, written, read, out, cents))
        }
        #endif

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
