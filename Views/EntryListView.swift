// Views/EntryListView.swift
import SwiftUI
import SwiftData

// MARK: - Filter & Sort Types

enum FilterType: CaseIterable, Hashable {
    case starred, inProgress, overdue, todo

    var label: String {
        switch self {
        case .starred:    return "Starred"
        case .inProgress: return "In Progress"
        case .overdue:    return "Overdue"
        case .todo:       return EntryStatus.todo.displayLabel
        }
    }
}

enum SortOption: String, CaseIterable {
    case recent   = "Recent"
    case dueDate  = "Due Date"
    case client   = "Client"
}

// MARK: - EntryListView (shared between Home screen & Client detail)

/// Unified filter/sort entry list, used on both the home screen and client
/// detail pages. Callers are responsible for excluding entries that are
/// already shown elsewhere (e.g. Today's Focus on the home screen) — this
/// view itself only ever excludes Quick Captures (never shown here) and
/// handles Done entries via its own collapsed section.
struct EntryListView: View {
    let entries: [Entry]
    var isClientScoped: Bool = false

    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    // Empty = no constraint (show everything). Each active pill ANDs in an
    // additional requirement — e.g. Starred + Overdue narrows to entries
    // that are both, not the union of the two.
    @State private var activeFilters: Set<FilterType> = []
    @State private var activeSort: SortOption = .recent
    @State private var doneExpanded = false

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    private var sortOptions: [SortOption] {
        isClientScoped ? [.recent, .dueDate] : SortOption.allCases
    }

    // Entries eligible for this component at all — Quick Captures are pinned
    // in their own section elsewhere and never appear here.
    private var eligibleEntries: [Entry] {
        entries.filter { !$0.isQuickAdd }
    }

    private func isOverdue(_ entry: Entry) -> Bool {
        guard entry.status != .done, let due = entry.dueDate else { return false }
        return due < todayStart
    }

    private func matches(_ entry: Entry, _ filter: FilterType) -> Bool {
        switch filter {
        case .starred:    return entry.isImportant
        case .inProgress: return entry.status == .inProgress
        case .overdue:    return isOverdue(entry)
        case .todo:       return entry.status == .todo
        }
    }

    private var filteredEntries: [Entry] {
        eligibleEntries.filter { entry in
            guard entry.status != .done else { return false }
            guard !activeFilters.isEmpty else { return true }
            return activeFilters.allSatisfy { matches(entry, $0) }
        }
    }

    private var sortedFlatEntries: [Entry] {
        switch activeSort {
        case .recent:
            return filteredEntries.sorted { $0.serviceDate > $1.serviceDate }
        case .dueDate:
            return filteredEntries.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (ad?, bd?): return ad < bd
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.serviceDate > b.serviceDate
                }
            }
        case .client:
            return filteredEntries.sorted { $0.serviceDate > $1.serviceDate }
        }
    }

    private var groupedByClient: [(client: String, entries: [Entry])] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.displayClientName }
        return grouped.keys.sorted().map { key in
            (client: key, entries: grouped[key]!.sorted { $0.serviceDate > $1.serviceDate })
        }
    }

    private var doneEntries: [Entry] {
        eligibleEntries
            .filter { $0.status == .done }
            .sorted { ($0.completedAt ?? $0.serviceDate) > ($1.completedAt ?? $1.serviceDate) }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                filterPillsRow
                sortBarRow
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
        } header: {
            Text("ENTRIES")
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.secondaryText)
                .tracking(0.5)
        }

        if !isClientScoped && activeSort == .client {
            ForEach(groupedByClient, id: \.client) { group in
                Section(group.client) {
                    ForEach(group.entries, id: \.persistentModelID) { entry in
                        entryRow(entry)
                    }
                }
            }
        } else {
            Section {
                if sortedFlatEntries.isEmpty {
                    Text("Nothing matches the current filters.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sortedFlatEntries, id: \.persistentModelID) { entry in
                        entryRow(entry)
                    }
                }
            }
        }

        if !doneEntries.isEmpty {
            Section {
                if doneExpanded {
                    ForEach(doneEntries, id: \.persistentModelID) { entry in
                        doneRow(entry)
                    }
                }
            } header: {
                Button {
                    withAnimation { doneExpanded.toggle() }
                } label: {
                    HStack {
                        Text("DONE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(theme.secondaryText)
                            .tracking(0.5)
                        Spacer()
                        Text("\(doneEntries.count)")
                            .font(.caption)
                            .foregroundStyle(theme.mutedText)
                        Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Controls

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FilterType.allCases, id: \.self) { filter in
                    let isActive = activeFilters.contains(filter)
                    Button {
                        if isActive { activeFilters.remove(filter) } else { activeFilters.insert(filter) }
                    } label: {
                        Text(filter.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isActive ? theme.accent : Color.clear))
                            .overlay(Capsule().strokeBorder(isActive ? Color.clear : theme.divider, lineWidth: 1))
                            .foregroundStyle(isActive ? .white : theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sortBarRow: some View {
        HStack(spacing: 16) {
            ForEach(sortOptions, id: \.self) { option in
                Button {
                    activeSort = option
                } label: {
                    VStack(spacing: 3) {
                        Text(option.rawValue)
                            .font(.caption.weight(activeSort == option ? .bold : .regular))
                            .foregroundStyle(activeSort == option ? theme.primaryText : theme.secondaryText)
                        Rectangle()
                            .fill(activeSort == option ? theme.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func entryRow(_ entry: Entry) -> some View {
        Group {
            if let raw = entry.setupAction, let action = SetupAction(rawValue: raw) {
                // Starter todo: tapping jumps to the app section it asks for.
                Button {
                    action.navigate()
                } label: {
                    HStack {
                        EntryListRow(entry: entry, isOverdue: isOverdue(entry))
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(theme.accent)
                            .imageScale(.large)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { EditEntryView(entry: entry) } label: {
                    EntryListRow(entry: entry, isOverdue: isOverdue(entry))
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(entry) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(entry) }
    }

    @ViewBuilder
    private func doneRow(_ entry: Entry) -> some View {
        NavigationLink { EditEntryView(entry: entry) } label: {
            EntryListDoneRow(entry: entry)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(entry) }
    }

    // MARK: - Swipe Actions (mirrors HomeView / ClientDetailView)

    @ViewBuilder
    private func trailingSwipe(_ entry: Entry) -> some View {
        if entry.status == .inProgress && entry.timerStartedAt != nil {
            Button { quickPauseAndAdd(entry) } label: {
                Label("Pause & Add", systemImage: "pause.circle")
            }.tint(theme.dueToday)
        } else if entry.status != .done {
            Button { quickStart(entry) } label: {
                Label("Start", systemImage: "play.circle")
            }.tint(theme.success)
        }
        Button { quickBump(entry, 0.25) } label: { Text("+15m") }.tint(theme.accent)
        Button { quickBump(entry, 0.5) }  label: { Text("+30m") }.tint(theme.accentHover)
    }

    @ViewBuilder
    private func leadingSwipe(_ entry: Entry) -> some View {
        Button {
            entry.isImportant.toggle()
            entry.markModified()
            try? ctx.save()
        } label: {
            Label(entry.isImportant ? "Unstar" : "Star",
                  systemImage: entry.isImportant ? "star.slash.fill" : "star.fill")
        }.tint(.yellow)

        if entry.status != .todo {
            Button {
                entry.status = .todo
                entry.timerStartedAt = nil
                entry.markModified()
                try? ctx.save()
            } label: {
                Label(EntryStatus.todo.displayLabel, systemImage: "circle")
            }.tint(theme.dueToday)
        }
        if entry.status != .inProgress {
            Button {
                entry.status = .inProgress
                if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
                entry.markModified()
                try? ctx.save()
            } label: {
                Label("In Progress", systemImage: "bolt.fill")
            }.tint(theme.running)
        }
        if entry.status != .done {
            Button { markDone(entry) } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }.tint(theme.success)
        }
    }

    private func quickStart(_ e: Entry) {
        e.status = .inProgress
        if e.timerStartedAt == nil { e.timerStartedAt = Date() }
        e.markModified()
        try? ctx.save()
    }
    private func quickPauseAndAdd(_ e: Entry) {
        guard e.timerStartedAt != nil else { return }
        let elapsed = e.runningElapsedHoursOrZero
        e.hours += elapsed
        e.timeLogsList.append(TimeLog(hours: elapsed, entry: e))
        e.timerStartedAt = nil
        e.markModified()
        try? ctx.save()
        NotificationManager.shared.cancelNoTimeLoggedReminder()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogsList.append(TimeLog(hours: h, entry: e))
        e.markModified()
        try? ctx.save()
        NotificationManager.shared.cancelNoTimeLoggedReminder()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        e.markModified()
        try? ctx.save()
    }
}

// MARK: - Row Bullet

/// Isolated subview so the repeating pulse animation only re-renders this
/// bullet, not the whole row / list.
private struct OverdueStarView: View {
    @State private var animate = false

    var body: some View {
        Image(systemName: "star.fill")
            .foregroundStyle(.red)
            .font(.system(size: 12))
            .opacity(animate ? 0.4 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}

private struct EntryListBullet: View {
    let isImportant: Bool
    let isOverdue: Bool

    var body: some View {
        if isImportant {
            if isOverdue {
                OverdueStarView()
            } else {
                Image(systemName: "star.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }
        } else {
            Circle()
                .fill(Color(.systemGray3))
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Rows

private struct EntryListRow: View {
    let entry: Entry
    let isOverdue: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            EntryListBullet(isImportant: entry.isImportant, isOverdue: isOverdue)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.displayClientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = entry.dueDate {
                Text(due, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(isOverdue ? theme.overdue : .secondary)
            } else {
                Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EntryListDoneRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.displayClientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let completed = entry.completedAt {
                Text(completed, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Quick Capture Row (yellow triangle bullet)

/// Pinned "Quick Captures" rows on the home screen — not part of the
/// filtered/sorted list, always shown regardless of active filters.
struct QuickCaptureRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "triangle.fill")
                .foregroundStyle(Color(.systemYellow))
                .font(.system(size: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.displayClientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
