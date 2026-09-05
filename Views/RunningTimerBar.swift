import SwiftUI
import SwiftData

/// Floating capsule visible on every screen while at least one timer runs.
/// Shows the most recently started timer with live elapsed time; tap to open
/// the entry (or a list when several timers run), pause banks the elapsed
/// time into a TimeLog like "Pause & Add" elsewhere in the app.
struct RunningTimerBar: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    /// True when hosted in an iOS 26 tab view bottom accessory, which
    /// draws its own glass capsule — skip our background there.
    var inAccessory: Bool = false

    @Query(filter: Entry.workOnlyPredicate) private var allEntries: [Entry]

    @State private var showRunningList = false
    @State private var editingEntry: Entry?
    @State private var pulse = false

    private var runningEntries: [Entry] {
        allEntries
            .filter { $0.timerStartedAt != nil }
            .sorted { ($0.timerStartedAt ?? .distantPast) > ($1.timerStartedAt ?? .distantPast) }
    }

    var body: some View {
        if let primary = runningEntries.first {
            Button {
                if runningEntries.count > 1 {
                    showRunningList = true
                } else {
                    editingEntry = primary
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(theme.running)
                        .frame(width: 9, height: 9)
                        .opacity(pulse ? 0.35 : 1)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }

                    Text(label(for: primary))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if runningEntries.count > 1 {
                        Text("+\(runningEntries.count - 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(theme.running)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(theme.running.opacity(0.15)))
                    }

                    Spacer(minLength: 4)

                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(elapsedString(primary))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(theme.running)
                    }

                    Button {
                        pause(primary)
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.running)
                            .accessibilityLabel("Pause timer")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if !inAccessory {
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay(Capsule().stroke(theme.running.opacity(0.45), lineWidth: 1))
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Timer running on \(primary.clientName)")
            .sheet(item: $editingEntry) { entry in
                if entry.isAlive {
                    NavigationStack { EditEntryView(entry: entry) }
                } else {
                    // Deleted while the sheet was open (from another device
                    // via CloudKit, or elsewhere in the app). Close instead
                    // of leaving an empty sheet the user can't act on.
                    Color.clear.onAppear { editingEntry = nil }
                }
            }
            .sheet(isPresented: $showRunningList) {
                RunningTimersListSheet(
                    entries: runningEntries,
                    onSelect: { entry in
                        showRunningList = false
                        editingEntry = entry
                    },
                    onPause: { entry in pause(entry) }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func label(for entry: Entry) -> String {
        let what = entry.detail.isEmpty ? entry.service : entry.detail
        return what.isEmpty ? entry.clientName : "\(entry.clientName) · \(what)"
    }

    private func elapsedString(_ entry: Entry) -> String {
        guard let started = entry.timerStartedAt else { return "" }
        let seconds = max(0, Int(Date().timeIntervalSince(started)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func pause(_ entry: Entry) {
        guard entry.timerStartedAt != nil else { return }
        let elapsed = entry.runningElapsedHoursOrZero
        entry.hours += elapsed
        entry.timeLogsList.append(TimeLog(hours: elapsed, entry: entry))
        entry.timerStartedAt = nil
        entry.markModified()
        try? ctx.save()
        NotificationManager.shared.cancelNoTimeLoggedReminder()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Tab view placement

private struct RunningTimerBarAttachment: ViewModifier {
    @Query(filter: Entry.workOnlyPredicate) private var allEntries: [Entry]

    // The iOS 26 accessory renders its glass capsule even when the content
    // view is empty, so only attach it while a timer is actually running.
    private var hasRunningTimer: Bool {
        allEntries.contains { $0.timerStartedAt != nil }
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if hasRunningTimer {
                content.tabViewBottomAccessory { RunningTimerBar(inAccessory: true) }
            } else {
                content
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                RunningTimerBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
        }
    }
}

extension View {
    /// Attaches the running-timer bar to a TabView: as a bottom accessory on
    /// iOS 26+ (sits above the floating tab bar) or a safe-area inset on
    /// earlier versions.
    func runningTimerBarAttachment() -> some View {
        modifier(RunningTimerBarAttachment())
    }
}

// MARK: - Multiple running timers

private struct RunningTimersListSheet: View {
    @Environment(\.appTheme) private var theme

    let entries: [Entry]
    let onSelect: (Entry) -> Void
    let onPause: (Entry) -> Void

    var body: some View {
        NavigationStack {
            List(entries, id: \.persistentModelID) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(entry.client?.accentColor ?? theme.running)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.clientName)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.detail.isEmpty ? entry.service : entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(elapsed(entry))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(theme.running)
                        }
                        Button {
                            onPause(entry)
                        } label: {
                            Image(systemName: "pause.circle.fill")
                                .font(.title3)
                                .foregroundStyle(theme.running)
                                .accessibilityLabel("Pause timer for \(entry.clientName)")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Running Timers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func elapsed(_ entry: Entry) -> String {
        guard let started = entry.timerStartedAt else { return "" }
        let seconds = max(0, Int(Date().timeIntervalSince(started)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
