import SwiftUI
import SwiftData

enum OnboardingPrefs {
    static let dismissed = "onboarding.dismissed"
    static let started = "onboarding.started"
}

/// Three-step guided setup shown on Home until the user has a client,
/// an entry, and has run a timer (or logged time) — or taps skip/done.
struct GettingStartedCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Entry.createdAt, order: .reverse) private var entriesStored: [Entry]
    /// Filtered in Swift, not in the `@Query` predicate. A predicate here
    /// wedges the app — see the note on `Entry.workOnly(_:)`.
    private var entries: [Entry] { Entry.workOnly(entriesStored) }

    @AppStorage(OnboardingPrefs.dismissed) private var dismissed = false

    @State private var showNewClient = false
    @State private var showNewEntry = false

    // Seeded setup todos don't count toward the user's own progress.
    private var realEntries: [Entry] { entries.filter { $0.setupAction == nil } }

    private var hasClient: Bool { !clients.isEmpty }
    private var hasEntry: Bool { !realEntries.isEmpty }
    private var hasTrackedTime: Bool {
        realEntries.contains { $0.timerStartedAt != nil || $0.hours > 0 || !$0.timeLogsList.isEmpty }
    }
    private var allDone: Bool { hasClient && hasEntry && hasTrackedTime }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(allDone ? "You're all set! 🎉" : "Welcome to BrickDot 👋")
                        .font(.headline)
                    Text(allDone
                         ? "That's the whole loop — capture work, track time, bill it."
                         : "Three quick steps and you're tracking billable time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !allDone {
                    Button {
                        withAnimation { dismissed = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Skip setup")
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 10) {
                GettingStartedStep(
                    index: 1,
                    title: "Add your first client",
                    subtitle: "Their hourly rate fills in every entry automatically",
                    done: hasClient,
                    enabled: true
                ) { showNewClient = true }

                GettingStartedStep(
                    index: 2,
                    title: "Create an entry",
                    subtitle: "A task or job you're doing for that client",
                    done: hasEntry,
                    enabled: hasClient
                ) { showNewEntry = true }

                GettingStartedStep(
                    index: 3,
                    title: "Start the timer",
                    subtitle: "One tap — BrickDot tracks the time for you",
                    done: hasTrackedTime,
                    enabled: hasEntry
                ) { startFirstTimer() }
            }

            if allDone {
                Button {
                    withAnimation { dismissed = true }
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.accent))
                        .foregroundStyle(theme.buttonText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accentLight.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(0.25), lineWidth: 1))
        .sheet(isPresented: $showNewClient) {
            NavigationStack { NewClientView() }
        }
        .sheet(isPresented: $showNewEntry) {
            NavigationStack {
                NewEntryView(onSaved: { showNewEntry = false }, prefillClient: clients.first)
            }
        }
    }

    private func startFirstTimer() {
        // Start the clock on the newest open entry; if everything is already
        // done, send them to create another entry to time instead.
        guard let entry = realEntries.first(where: { $0.status != .done }) else {
            showNewEntry = true
            return
        }
        entry.status = .inProgress
        if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
        try? ctx.save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Step Row

private struct GettingStartedStep: View {
    @Environment(\.appTheme) private var theme

    let index: Int
    let title: String
    let subtitle: String
    let done: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(done ? theme.success : (enabled ? theme.accent : Color(.systemGray4)))
                        .frame(width: 28, height: 28)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(done ? .regular : .semibold))
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if !done && enabled {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(done ? Color.clear : Color(.systemBackground).opacity(enabled ? 1 : 0.5))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done || !enabled)
        .animation(.default, value: done)
    }
}
