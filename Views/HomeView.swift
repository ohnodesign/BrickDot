import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]

    @State private var showNewEntry = false
    @State private var searchText = ""
    @State private var showSearch = false
    @Query private var profiles: [UserProfile]
    private var profile: UserProfile? { profiles.first }

    @State private var expandedSections: Set<String> = []

    private func isExpanded(_ key: String) -> Bool { expandedSections.contains(key) }
    private func toggleExpanded(_ key: String) { if expandedSections.contains(key) { expandedSections.remove(key) } else { expandedSections.insert(key) } }

    private func statusColor(_ status: EntryStatus) -> Color {
        switch status {
        case .todo:       return theme.dueToday
        case .inProgress: return theme.running
        case .done:       return theme.success
        }
    }

    var body: some View {
            List {
                // MARK: - Search bar (iPhone)
                if showSearch && sizeClass == .compact {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search entries…", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                // MARK: - Greeting & Today's Focus
                if searchText.isEmpty {
                    Section {
                        GreetingText(name: profile?.displayName ?? "")
                            .listRowSeparator(.hidden)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                    if !todayFocusEntries.isEmpty {
                        Section {
                            ForEach(Array(todayFocusEntries.prefix(3).enumerated()), id: \.element.persistentModelID) { index, entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    FocusRow(index: index, entry: entry)
                                }
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            sectionHeader("Today's Focus", count: todayFocusEntries.count, cap: 3, key: "focus")
                        }
                    }
                }

                // MARK: - Dashboard (iPhone only — iPad shows this in the sidebar)
                if sizeClass == .compact {
                    Section {
                        DashboardRow(
                            overdueCount: overdueEntries.count,
                            dueTodayCount: allDueTodayCount,
                            timersRunning: timersRunningCount,
                            weekAmount: thisWeekAmount
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                // MARK: - Action List
                if actionEntries.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.largeTitle)
                                .foregroundStyle(theme.success)
                            Text("All caught up!")
                                .font(.headline)
                            Text("No open entries right now.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    // Overdue
                    cappedSection(key: "overdue", entries: overdueEntries, badge: .overdue,
                                  icon: "exclamationmark.triangle.fill", title: "Overdue", tint: theme.overdue)

                    // Due Today
                    cappedSection(key: "today", entries: dueTodayEntries, badge: .dueToday,
                                  icon: "sun.max.fill", title: "Due Today", tint: theme.dueToday)

                    // Quick Captures
                    cappedSection(key: "quickadd", entries: quickAddEntries, badge: ActionRowBadge.none,
                                  icon: "plus.circle.fill", title: "Quick Captures", tint: theme.quickCapture, iconScale: 1.0)

                    // In Progress (with timers)
                    cappedSection(key: "inprogress", entries: inProgressEntries, badge: ActionRowBadge.none,
                                  icon: "bolt.fill", title: "In Progress", tint: theme.running)

                    // Upcoming
                    cappedSection(key: "upcoming", entries: upcomingEntries, badge: nil,
                                  icon: "calendar.badge.clock", title: "Upcoming", tint: theme.accent)

                    // Backlog
                    cappedSection(key: "backlog", entries: backlogEntries, badge: ActionRowBadge.none,
                                  icon: "tray.fill", title: "Backlog", tint: theme.mutedText)
                }

                // MARK: - Done (collapsed)
                if !doneEntries.isEmpty {
                    let doneCap = 5
                    let doneExpanded = isExpanded("done")
                    Section {
                        ForEach(doneExpanded ? Array(doneEntries.prefix(20)) : Array(doneEntries.prefix(doneCap))) { entry in
                            NavigationLink { EditEntryView(entry: entry) } label: {
                                ActionRow(entry: entry, badge: .none)
                            }
                        }
                    } header: {
                        sectionHeader("Done", count: doneEntries.count, cap: doneCap, key: "done")
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(6)
            .listSectionSeparator(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showNewEntry) {
                QuickAddView(onSaved: { showNewEntry = false })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "house")
                            .imageScale(.large)
                            .foregroundStyle(Color(.darkGray))
                            .accessibilityLabel("Home")
                    }
                    ToolbarItem(placement: .principal) {
                        Text(profile?.companyName.isEmpty == false ? profile!.companyName : "BrickDot")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                withAnimation {
                                    showSearch.toggle()
                                    if !showSearch { searchText = "" }
                                }
                            } label: {
                                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                                    .imageScale(.large)
                                    .foregroundStyle(Color(.darkGray))
                                    .accessibilityLabel("Search")
                            }
                            Button { showNewEntry = true } label: {
                                ZStack {
                                    Circle()
                                        .fill(theme.quickCapture)
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .accessibilityLabel("New Entry")
                            }
                        }
                    }
                }
            }
    }

    // MARK: - Swipe Actions
    @ViewBuilder
    private func entrySwipeActions(_ entry: Entry) -> some View {
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
    private func entryLeadingSwipeActions(_ entry: Entry) -> some View {
        // Star / Unstar
        Button {
            entry.isImportant.toggle()
            try? ctx.save()
        } label: {
            Label(entry.isImportant ? "Unstar" : "Star",
                  systemImage: entry.isImportant ? "star.slash.fill" : "star.fill")
        }
        .tint(.yellow)

        // Status changes
        if entry.status != .todo {
            Button {
                entry.status = .todo
                entry.timerStartedAt = nil
                try? ctx.save()
            } label: {
                Label("To Do", systemImage: "circle")
            }
            .tint(theme.dueToday)
        }
        if entry.status != .inProgress {
            Button {
                entry.status = .inProgress
                if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
                try? ctx.save()
            } label: {
                Label("In Progress", systemImage: "bolt.fill")
            }
            .tint(theme.running)
        }
        if entry.status != .done {
            Button {
                entry.status = .done
                entry.timerStartedAt = nil
                entry.completedAt = Date()
                try? ctx.save()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }
            .tint(theme.success)
        }
    }

    // MARK: - Quick Actions
    private func quickStart(_ e: Entry) {
        e.status = .inProgress
        if e.timerStartedAt == nil { e.timerStartedAt = Date() }
        try? ctx.save()
    }
    private func quickPauseAndAdd(_ e: Entry) {
        guard e.timerStartedAt != nil else { return }
        let elapsed = e.runningElapsedHoursOrZero
        e.hours += elapsed
        e.timeLogsList.append(TimeLog(hours: elapsed, entry: e))
        e.timerStartedAt = nil
        try? ctx.save()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogsList.append(TimeLog(hours: h, entry: e))
        try? ctx.save()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        try? ctx.save()
    }

    // MARK: - Capped Section Builder

    @ViewBuilder
    private func cappedSection(key: String, entries: [Entry], badge: ActionRowBadge?, icon: String, title: String, tint: Color, iconScale: CGFloat = 1.0) -> some View {
        if !entries.isEmpty {
            let cap = 3
            let expanded = isExpanded(key)
            let displayed = expanded ? entries : Array(entries.prefix(cap))

            Section {
                ForEach(displayed) { entry in
                    NavigationLink { EditEntryView(entry: entry) } label: {
                        ActionRow(entry: entry, badge: badge ?? dueBadge(for: entry))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        entrySwipeActions(entry)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        entryLeadingSwipeActions(entry)
                    }
                }
            } header: {
                sectionHeader(title, count: entries.count, cap: cap, key: key)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int, cap: Int, key: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(theme.secondaryText)
                .tracking(0.5)
            Spacer()
            if count > cap {
                Button {
                    withAnimation { toggleExpanded(key) }
                } label: {
                    Text(isExpanded(key) ? "Show less" : "View all")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Entry Sorting & Filtering

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }
    private var todayEnd: Date { cal.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? Date() }
    private var weekEnd: Date { Date().bdEndOfWeek }

    private func matchesSearch(_ entry: Entry) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        return entry.clientName.lowercased().contains(q)
            || entry.service.lowercased().contains(q)
            || entry.detail.lowercased().contains(q)
            || entry.notes.lowercased().contains(q)
    }

    private var openEntries: [Entry] {
        allEntries.filter { $0.status != .done && matchesSearch($0) }
    }

    private var overdueEntries: [Entry] {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < todayStart
        }.sorted(by: prioritySort)
    }

    private var allDueTodayCount: Int {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }.count
    }

    private var dueTodayEntries: [Entry] {
        openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd && e.status != .inProgress
        }.sorted(by: prioritySort)
    }

    private var inProgressEntries: [Entry] {
        openEntries.filter { $0.status == .inProgress }
            .sorted { a, b in
                // Timers running first
                if (a.timerStartedAt != nil) != (b.timerStartedAt != nil) {
                    return a.timerStartedAt != nil
                }
                return prioritySort(a, b)
            }
    }

    private var quickAddEntries: [Entry] {
        openEntries.filter { $0.isQuickAdd && $0.status == .todo }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var upcomingEntries: [Entry] {
        let shown = Set(overdueEntries.map(\.persistentModelID))
            .union(dueTodayEntries.map(\.persistentModelID))
            .union(inProgressEntries.map(\.persistentModelID))
            .union(quickAddEntries.map(\.persistentModelID))

        return openEntries.filter { e in
            guard !shown.contains(e.persistentModelID) else { return false }
            guard let due = e.dueDate else { return false }
            return due > todayEnd
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var backlogEntries: [Entry] {
        let shown = Set(overdueEntries.map(\.persistentModelID))
            .union(dueTodayEntries.map(\.persistentModelID))
            .union(inProgressEntries.map(\.persistentModelID))
            .union(quickAddEntries.map(\.persistentModelID))
            .union(upcomingEntries.map(\.persistentModelID))

        return openEntries.filter { !shown.contains($0.persistentModelID) }
            .sorted(by: prioritySort)
    }

    private var actionEntries: [Entry] { openEntries }

    // Today's Focus: top 5 most urgent entries (overdue → due today → in progress → starred)
    private var todayFocusEntries: [Entry] {
        var focus: [Entry] = []
        // Overdue first (ignore search filter for focus)
        let allOpen = allEntries.filter { $0.status != .done }
        let overdue = allOpen.filter { e in
            guard let due = e.dueDate else { return false }
            return due < todayStart
        }.sorted(by: prioritySort)
        focus.append(contentsOf: overdue)

        // Due today
        let today = allOpen.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }.sorted(by: prioritySort)
        focus.append(contentsOf: today)

        // In progress with timers
        let running = allOpen.filter { $0.status == .inProgress && $0.timerStartedAt != nil }
        for e in running where !focus.contains(where: { $0.persistentModelID == e.persistentModelID }) {
            focus.append(e)
        }

        // Starred (only if due today, overdue, or no due date — not future)
        let starred = allOpen.filter { e in
            guard e.isImportant else { return false }
            if let due = e.dueDate { return due <= todayEnd }
            return true
        }.sorted(by: prioritySort)
        for e in starred where !focus.contains(where: { $0.persistentModelID == e.persistentModelID }) {
            focus.append(e)
        }

        return Array(focus.prefix(5))
    }

    private var todayFocusRevenue: Double {
        todayFocusEntries.reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    private var doneEntries: [Entry] {
        allEntries.filter { $0.status == .done && matchesSearch($0) }
            .sorted { ($0.completedAt ?? $0.serviceDate) > ($1.completedAt ?? $1.serviceDate) }
    }

    private var timersRunningCount: Int {
        allEntries.filter { $0.status == .inProgress && $0.timerStartedAt != nil }.count
    }

    private var thisWeekAmount: Double {
        let start = Date().bdStartOfWeek
        let end = Date().bdEndOfWeek
        return allEntries
            .filter { $0.status == .done && ($0.completedAt ?? $0.serviceDate) >= start && ($0.completedAt ?? $0.serviceDate) <= end }
            .reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    private func prioritySort(_ a: Entry, _ b: Entry) -> Bool {
        // Starred first
        if a.isImportant != b.isImportant { return a.isImportant }
        // Then by due date (soonest first), nil last
        switch (a.dueDate, b.dueDate) {
        case let (ad?, bd?): return ad < bd
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.serviceDate > b.serviceDate
        }
    }

    private func dueBadge(for entry: Entry) -> ActionRowBadge {
        guard let due = entry.dueDate else { return .none }
        if due < todayStart { return .overdue }
        if due <= todayEnd { return .dueToday }
        if due <= weekEnd { return .dueSoon }
        return .none
    }
}

// MARK: - Dashboard Row

private struct DashboardRow: View {
    let overdueCount: Int
    let dueTodayCount: Int
    let timersRunning: Int
    let weekAmount: Double
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            DashboardPill(
                icon: "exclamationmark.triangle.fill",
                tint: theme.overdue,
                value: "\(overdueCount)",
                label: "Overdue"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "sun.max.fill",
                tint: theme.dueToday,
                value: "\(dueTodayCount)",
                label: "Today"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "timer",
                tint: theme.running,
                value: "\(timersRunning)",
                label: "Running"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "dollarsign.circle.fill",
                tint: theme.revenue,
                value: weekAmount.shortCurrency,
                label: "This Week"
            )
        }
    }
}

private struct DashboardPill: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Action Row

enum ActionRowBadge {
    case none, overdue, dueToday, dueSoon
}

private struct ActionRow: View {
    let entry: Entry
    let badge: ActionRowBadge

    @Environment(\.appTheme) private var theme

    @State private var tick = Date()

    private var hasRunningTimer: Bool {
        entry.status == .inProgress && entry.timerStartedAt != nil
    }

    private var clientColor: Color {
        entry.client?.accentColor ?? ClientColors.palette[0].color
    }

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(
                color: statusColor(entry.status),
                isImportant: entry.isImportant,
                pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)

                    if let due = entry.dueDate, badge != .none {
                        dueBadgeView(due: due)
                    }
                }

                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if entry.status == .inProgress, entry.timerStartedAt != nil {
                    Text(entry.runningElapsedHoursOrZero.hoursMinutesString)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.running.opacity(0.15)))
                        .foregroundStyle(theme.running)
                } else {
                    Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if entry.hours > 0 {
                    Text("\(entry.hours, specifier: "%.1f")h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .task(id: hasRunningTimer) {
            guard hasRunningTimer else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
            }
        }
    }

    @ViewBuilder
    private func dueBadgeView(due: Date) -> some View {
        switch badge {
        case .overdue:
            badgePill("Overdue", color: theme.overdue)
        case .dueToday:
            badgePill("Today", color: theme.dueToday)
        case .dueSoon:
            badgePill(due.formatted(.dateTime.month(.abbreviated).day()), color: theme.accent)
        case .none:
            EmptyView()
        }
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

// MARK: - Greeting & Focus Components

private struct GreetingText: View {
    let name: String
    @Environment(\.appTheme) private var theme
    @AppStorage(AppPrefsKey.showDailyPhrase) private var showDailyPhrase = true

    private var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    private static let dailyPhrases: [String] = [
        "Let's make today productive.",
        "Small steps, big results.",
        "Your best work starts now.",
        "\"The secret of getting ahead is getting started.\"",
        "One task at a time.",
        "Build something you're proud of.",
        "Progress over perfection.",
        "\"Do what you can, with what you have, where you are.\"",
        "Today's effort is tomorrow's momentum.",
        "Stay focused, stay sharp.",
        "Great things take time — keep going.",
        "\"Simplicity is the ultimate sophistication.\"",
        "Clear the decks, own the day.",
        "Your clients are counting on you.",
        "\"Well begun is half done.\"",
        "Make it happen.",
        "The work you do today matters.",
        "\"Quality is not an act, it is a habit.\"",
        "Less talk, more build.",
        "You've got this."
    ]

    private var dailyPhrase: String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return Self.dailyPhrases[day % Self.dailyPhrases.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(greeting)\(firstName.isEmpty ? "" : " \(firstName)")")
                .font(.system(size: 34, weight: .bold, design: .serif))
            if showDailyPhrase {
                Text(dailyPhrase)
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedText)
                    .padding(.bottom, 8)
            }
        }
    }
}

private struct FocusRow: View {
    let index: Int
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().strokeBorder(Color(.systemGray4), lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.detail.isEmpty ? entry.service : entry.detail)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
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

// MARK: - Helpers

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

private extension Double {
    var shortCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = code
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
}
