import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    // Owned by RootView so the conversation — and any confirmation waiting
    // for a tap — survives leaving the tab.
    @Environment(CoachSession.self) private var session
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
            } else if session.messages.isEmpty && !session.isLoading {
                emptyState
            } else {
                chatList
            }

            if !session.pendingChanges.isEmpty {
                CoachConfirmationCard(
                    changes: session.pendingChanges,
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
            if !session.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        session.clear()
                    }
                    .font(.subheadline)
                }
            }
        }
        .onChange(of: speech.transcript) { _, newValue in
            if !newValue.isEmpty {
                session.draft = newValue
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
                    ForEach(session.visibleMessages) { msg in
                        ChatBubble(message: msg)
                            .equatable()
                            .id(msg.id)
                    }
                    if session.isLoading {
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
                    if let error = session.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(theme.overdue)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: session.messages.count) { _, _ in
                guard let lastID = session.messages.last?.id else { return }
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
        @Bindable var session = session
        return HStack(spacing: 8) {
            Button {
                toggleSpeech()
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(speech.isRecording ? theme.overdue : .secondary)
                    .frame(width: 36, height: 36)
            }

            TextField("Ask your coach...", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                .onSubmit { sendMessage(session.draft) }

            Button {
                sendMessage(session.draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(.systemGray3) : theme.accent)
            }
            .disabled(session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isLoading)
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
        if speech.isRecording { speech.stopRecording() }
        session.send(text,
                     context: ctx,
                     userName: profile?.displayName ?? "",
                     companyName: profile?.companyName ?? "")
    }

    private func applyChanges() {
        session.applyChanges(context: ctx,
                             userName: profile?.displayName ?? "",
                             companyName: profile?.companyName ?? "")
    }

    private func dismissChanges() {
        session.dismissChanges(context: ctx,
                               userName: profile?.displayName ?? "",
                               companyName: profile?.companyName ?? "")
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
                        Text(message.toolCalls.map(\.name).joined(separator: ", "))
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
