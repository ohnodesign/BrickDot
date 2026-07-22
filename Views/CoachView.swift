import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    @State private var messages: [AIService.Message] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var pendingChanges: [PendingChange] = []
    @StateObject private var speech = SpeechRecognizer()

    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    private let quickPrompts = [
        "What should I work on?",
        "What's overdue?",
        "Summarize my day",
        "Any tasks stalling?"
    ]

    // Hide the internal tool_result turns; show only user/assistant chat.
    private var visibleMessages: [AIService.Message] {
        messages.filter { $0.toolResults.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !AIService.hasAPIKey {
                apiKeyPrompt
            } else if messages.isEmpty && !isLoading {
                emptyState
            } else {
                chatList
            }

            if !pendingChanges.isEmpty {
                CoachConfirmationCard(
                    changes: pendingChanges,
                    accent: theme.accent,
                    onApply: applyChanges,
                    onDismiss: dismissChanges
                )
                .equatable()
            } else if AIService.hasAPIKey {
                inputBar
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        messages.removeAll()
                        error = nil
                        pendingChanges = []
                    }
                    .font(.subheadline)
                }
            }
        }
        .onChange(of: speech.transcript) { _, newValue in
            if !newValue.isEmpty {
                input = newValue
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(theme.accent)
            Text("AI Work Coach")
                .font(.title2.weight(.bold))
            Text("Ask me what to work on, or tell me to start timers, reschedule, focus, and update tasks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    Button {
                        sendMessage(prompt)
                    } label: {
                        Text(prompt)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - API Key Prompt

    private var apiKeyPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.accent)
            Text("API Key Required")
                .font(.title3.weight(.bold))
            Text("Add your Anthropic API key in Settings to enable the AI coach.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Chat List

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleMessages) { msg in
                        ChatBubble(message: msg)
                            .equatable()
                            .id(msg.id)
                    }
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .id("loading")
                    }
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(theme.overdue)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                // Defer to the next runloop so freshly-appended rows lay out
                // before scrolling. Scrolling to a not-yet-rendered row in a
                // LazyVStack can send SwiftUI into a layout loop (a hang).
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                toggleSpeech()
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(speech.isRecording ? theme.overdue : .secondary)
                    .frame(width: 36, height: 36)
            }

            TextField("Ask your coach...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                .onSubmit { sendMessage(input) }

            Button {
                sendMessage(input)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.systemGray3) : theme.accent)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Speech

    private func toggleSpeech() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            speech.transcript = ""
            Task {
                let granted = await speech.requestPermission()
                if granted {
                    speech.startRecording()
                }
            }
        }
    }

    // MARK: - Send

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if speech.isRecording { speech.stopRecording() }

        messages.append(AIService.Message(role: .user, content: trimmed))
        input = ""
        error = nil
        isLoading = true

        let history = messages
        let container = ctx.container
        let userName = profile?.displayName ?? ""
        let company = profile?.companyName ?? ""

        Task {
            // Build the task payload off the main thread — serializing every
            // entry (and encoding their ids) is too heavy for the main thread.
            let taskJSON = await PayloadBuilder(modelContainer: container).build()
            let service = AIService(taskJSON: taskJSON, userName: userName, companyName: company)
            do {
                let response = try await service.send(messages: history)

                await MainActor.run {
                    if response.toolCalls.isEmpty {
                        messages.append(AIService.Message(role: .assistant, content: response.text))
                    } else {
                        messages.append(AIService.Message(
                            role: .assistant,
                            content: response.text,
                            toolCalls: response.toolCalls
                        ))
                        let resolver = EntryResolver(ctx)
                        pendingChanges = response.toolCalls.map { call in
                            PendingChange(summary: describe(call, resolver: resolver), toolCall: call)
                        }
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Apply / Dismiss

    private func applyChanges() {
        // Apply on the main context and save once — the same path the task
        // editor uses for a single-field change, which saves cleanly.
        let calls = pendingChanges.map { $0.toolCall }
        pendingChanges = []

        var blocks: [ToolResultBlock] = []
        for call in calls {
            let text = CoachToolExecutor.execute(call, context: ctx)
            blocks.append(ToolResultBlock(toolUseID: call.id, content: text))
        }
        try? ctx.save()

        messages.append(AIService.Message(role: .user, content: "", toolResults: blocks))
        let summary: String
        if blocks.count == 1 {
            summary = blocks[0].content
        } else {
            summary = "Done:\n" + blocks.map { "• \($0.content)" }.joined(separator: "\n")
        }
        messages.append(AIService.Message(role: .assistant, content: summary))
    }

    private func dismissChanges() {
        let results = pendingChanges.map {
            ToolResultBlock(toolUseID: $0.toolCall.id, content: "Change dismissed by the user.")
        }
        messages.append(AIService.Message(role: .user, content: "", toolResults: results))
        messages.append(AIService.Message(role: .assistant, content: "No problem — dismissed."))
        pendingChanges = []
    }

    // MARK: - Change Summaries (read-only)

    private func describe(_ call: CoachToolCall, resolver: EntryResolver) -> String {
        func names(_ key: String) -> String {
            let ids = call.stringArray(key)
            let entries = resolver.entries(ids)
            if entries.isEmpty { return "\(ids.count) task(s)" }
            let ns = entries.map { CoachToolFormat.name($0) }
            if ns.count == 1 { return "\"\(ns[0])\"" }
            if ns.count <= 3 { return ns.map { "\"\($0)\"" }.joined(separator: ", ") }
            return "\(ns.count) tasks"
        }

        switch call.name {
        case "moveTaskToFocus":
            return "Star \(names("taskIds")) for Today's Focus"
        case "removeFromFocus":
            return "Remove \(names("taskIds")) from Today's Focus"
        case "updateDueDate":
            if let shift = call.string("shift") {
                return "Move due date for \(names("taskIds")) to \(CoachToolFormat.shiftLabel(shift))"
            } else if let ds = call.string("dueDate") {
                return "Set due date for \(names("taskIds")) to \(ds)"
            }
            return "Update due date for \(names("taskIds"))"
        case "updateTaskStatus":
            let raw = call.string("status") ?? ""
            return "Mark \(names("taskIds")) as \(CoachToolFormat.statusFrom(raw).map(CoachToolFormat.statusLabel) ?? raw)"
        case "bulkUpdate":
            return "Apply \(call.objectArray("updates").count) changes to tasks"
        case "start_timer":
            return "Start timer on \"\(call.string("task_description") ?? "task")\""
        case "stop_timer":
            return "Stop timer on \"\(call.string("task_description") ?? "task")\""
        case "mark_done":
            return "Mark \"\(call.string("task_description") ?? "task")\" as done"
        case "add_time":
            return "Add \(call.string("minutes") ?? "?") min to \"\(call.string("task_description") ?? "task")\""
        case "set_priority":
            return "Set \"\(call.string("task_description") ?? "task")\" priority to \(call.string("priority") ?? "?")"
        default:
            return call.name
        }
    }
}

// MARK: - Confirmation Card

private struct CoachConfirmationCard: View, Equatable {
    let changes: [PendingChange]
    let accent: Color
    let onApply: () -> Void
    let onDismiss: () -> Void

    // Compare by change identity (closures are stable methods, ignored here) so
    // SwiftUI never structurally walks the PendingChange values.
    static func == (lhs: CoachConfirmationCard, rhs: CoachConfirmationCard) -> Bool {
        lhs.changes.map(\.id) == rhs.changes.map(\.id) && lhs.accent == rhs.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.secondary)
                Text(changes.count == 1 ? "Proposed change" : "Proposed changes")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ForEach(changes) { change in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(accent)
                        .padding(.top, 6)
                    Text(change.summary)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    onApply()
                } label: {
                    Text(changes.count == 1 ? "Apply" : "Apply All")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(.bar)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View, Equatable {
    let message: AIService.Message
    @Environment(\.appTheme) private var theme

    // Messages are append-only and never mutated, so identity is sufficient.
    // Conforming to Equatable + `.equatable()` makes SwiftUI compare rows by id
    // instead of structurally walking the whole message (which was pinning the
    // main thread in AttributeGraph's value comparison).
    static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
        lhs.message.id == rhs.message.id
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.body)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(message.role == .user ? theme.accent : Color(.systemGray6))
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                }

                if !message.toolCalls.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.caption2)
                        Text("\(message.toolCalls.count) proposed change\(message.toolCalls.count == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
    }
}
