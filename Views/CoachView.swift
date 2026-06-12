import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    @State private var messages: [AIService.Message] = []
    @State private var input = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var pendingAction: AIService.ToolUseRequest?
    @StateObject private var speech = SpeechRecognizer()

    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    private let quickPrompts = [
        "What should I work on?",
        "What's overdue?",
        "Summarize my day",
        "Any tasks stalling?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if !AIService.hasAPIKey {
                apiKeyPrompt
            } else if messages.isEmpty && !isLoading {
                emptyState
            } else {
                chatList
            }

            if let action = pendingAction {
                confirmationBar(action)
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
                        pendingAction = nil
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
            Text("Ask me what to work on, or tell me to start timers, mark tasks done, and more.")
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
                    ForEach(messages) { msg in
                        if msg.toolResultID == nil {
                            ChatBubble(message: msg, theme: theme)
                                .id(msg.id)
                        }
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
                withAnimation {
                    if let lastID = messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
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

    // MARK: - Confirmation Bar

    private func confirmationBar(_ action: AIService.ToolUseRequest) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconForTool(action.name))
                    .foregroundStyle(theme.accent)
                Text(action.displayDescription)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button {
                    denyAction(action)
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray5)))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Button {
                    confirmAction(action)
                } label: {
                    Text("Confirm")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "start_timer": return "play.circle.fill"
        case "stop_timer": return "pause.circle.fill"
        case "mark_done": return "checkmark.circle.fill"
        case "add_time": return "clock.badge.fill"
        case "set_priority": return "star.fill"
        default: return "wrench.fill"
        }
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

        let userMsg = AIService.Message(role: .user, content: trimmed)
        messages.append(userMsg)
        input = ""
        error = nil
        isLoading = true

        let taskJSON = TaskDataSerializer.buildPayload(context: ctx)
        let history = messages
        let service = AIService(
            taskJSON: taskJSON,
            userName: profile?.displayName ?? "",
            companyName: profile?.companyName ?? ""
        )

        Task {
            do {
                let response = try await service.send(messages: history)

                await MainActor.run {
                    if let toolUse = response.toolUse {
                        let assistantMsg = AIService.Message(
                            role: .assistant,
                            content: response.text,
                            toolUse: toolUse
                        )
                        messages.append(assistantMsg)
                        pendingAction = toolUse
                    } else {
                        let assistantMsg = AIService.Message(role: .assistant, content: response.text)
                        messages.append(assistantMsg)
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

    // MARK: - Tool Execution

    private func confirmAction(_ action: AIService.ToolUseRequest) {
        let result = executeAction(action)
        pendingAction = nil

        let toolResultMsg = AIService.Message(
            role: .user,
            content: result,
            toolResultID: action.id
        )
        messages.append(toolResultMsg)

        let confirmMsg = AIService.Message(role: .assistant, content: result)
        messages.append(confirmMsg)
    }

    private func denyAction(_ action: AIService.ToolUseRequest) {
        pendingAction = nil

        let toolResultMsg = AIService.Message(
            role: .user,
            content: "Action cancelled by user.",
            toolResultID: action.id
        )
        messages.append(toolResultMsg)

        let cancelMsg = AIService.Message(role: .assistant, content: "No problem — cancelled.")
        messages.append(cancelMsg)
    }

    private func executeAction(_ action: AIService.ToolUseRequest) -> String {
        let desc = action.input["task_description"] ?? ""
        guard let entry = findEntry(matching: desc) else {
            return "Could not find a task matching \"\(desc)\"."
        }

        switch action.name {
        case "start_timer":
            entry.status = .inProgress
            if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
            try? ctx.save()
            return "Started timer on \"\(entry.detail.isEmpty ? entry.service : entry.detail)\"."

        case "stop_timer":
            guard let started = entry.timerStartedAt else {
                return "No timer running on that task."
            }
            let elapsed = Date().timeIntervalSince(started) / 3600
            entry.hours += elapsed
            entry.timeLogsList.append(TimeLog(hours: elapsed, entry: entry))
            entry.timerStartedAt = nil
            try? ctx.save()
            let mins = Int(elapsed * 60)
            return "Stopped timer on \"\(entry.detail.isEmpty ? entry.service : entry.detail)\" — logged \(mins) min."

        case "mark_done":
            entry.status = .done
            entry.timerStartedAt = nil
            entry.completedAt = Date()
            try? ctx.save()
            return "Marked \"\(entry.detail.isEmpty ? entry.service : entry.detail)\" as done."

        case "add_time":
            let minutes = Double(action.input["minutes"] ?? "0") ?? 0
            let hours = minutes / 60
            entry.hours += hours
            entry.timeLogsList.append(TimeLog(hours: hours, entry: entry))
            try? ctx.save()
            return "Added \(Int(minutes)) min to \"\(entry.detail.isEmpty ? entry.service : entry.detail)\"."

        case "set_priority":
            let isHigh = action.input["priority"] == "high"
            entry.isImportant = isHigh
            try? ctx.save()
            return "Set \"\(entry.detail.isEmpty ? entry.service : entry.detail)\" to \(isHigh ? "high" : "normal") priority."

        default:
            return "Unknown action."
        }
    }

    private func findEntry(matching description: String) -> Entry? {
        let allEntries = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []
        let open = allEntries.filter { $0.status != .done }
        let query = description.lowercased()

        if let exact = open.first(where: {
            $0.detail.lowercased() == query || $0.service.lowercased() == query
        }) {
            return exact
        }

        return open.first(where: {
            $0.detail.lowercased().contains(query) ||
            $0.service.lowercased().contains(query) ||
            query.contains($0.detail.lowercased()) ||
            query.contains($0.service.lowercased())
        })
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: AIService.Message
    let theme: AppTheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? theme.accent : Color(.systemGray6))
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)

                if let toolUse = message.toolUse {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                            .font(.caption2)
                        Text(toolUse.displayDescription)
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
