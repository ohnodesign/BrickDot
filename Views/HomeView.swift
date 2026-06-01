import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]

    @State private var showNewEntry = false
    @State private var searchText = ""
    @AppStorage("home.showDoneSection") private var showDoneSection = false
    @AppStorage("user.displayName") private var displayName = ""

    @State private var expandedSections: Set<String> = []

    private func isExpanded(_ key: String) -> Bool { expandedSections.contains(key) }
    private func toggleExpanded(_ key: String) { if expandedSections.contains(key) { expandedSections.remove(key) } else { expandedSections.insert(key) } }

    var body: some View {
            List {
                // MARK: - Greeting & Today's Focus
                if searchText.isEmpty {
                    Section {
                        GreetingText(name: displayName)
                            .listRowSeparator(.hidden)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                    if !todayFocusEntries.isEmpty {
                        Section {
                            Text("Today's Focus")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)

                            ForEach(Array(todayFocusEntries.enumerated()), id: \.element.persistentModelID) { index, entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    FocusRow(index: index, entry: entry)
                                }
                            }

                            HStack {
                                Text("Potential Revenue:")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(todayFocusRevenue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                    .font(.subheadline.weight(.bold))
                            }
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
                                .foregroundStyle(.green)
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
                                  icon: "exclamationmark.triangle.fill", title: "Overdue", tint: .red)

                    // Due Today
                    cappedSection(key: "today", entries: dueTodayEntries, badge: .dueToday,
                                  icon: "sun.max.fill", title: "Due Today", tint: .orange)

                    // Quick Adds
                    cappedSection(key: "quickadd", entries: quickAddEntries, badge: ActionRowBadge.none,
                                  icon: "hare.fill", title: "Quick Adds", tint: Color(red: 0.75, green: 0.60, blue: 0.0), iconScale: 0.8)

                    // In Progress (with timers)
                    cappedSection(key: "inprogress", entries: inProgressEntries, badge: ActionRowBadge.none,
                                  icon: "bolt.fill", title: "In Progress", tint: Color.brick)

                    // Up Next
                    cappedSection(key: "upnext", entries: upNextEntries, badge: nil,
                                  icon: "arrow.right.circle.fill", title: "Up Next", tint: .accent)

                    // Backlog
                    cappedSection(key: "backlog", entries: backlogEntries, badge: ActionRowBadge.none,
                                  icon: "tray.fill", title: "Backlog", tint: .secondary)
                }

                // MARK: - Done (collapsed)
                if !doneEntries.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showDoneSection) {
                            ForEach(Array(doneEntries.prefix(20))) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: .none)
                                }
                            }
                            if doneEntries.count > 20 {
                                Text("View all in Log tab")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Done")
                                Spacer()
                                Text("\(doneEntries.count)")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(4)
            .navigationTitle("Ohno Design")
            .if(sizeClass == .compact) { view in
                view.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            }
            .sheet(isPresented: $showNewEntry) {
                QuickAddView(onSaved: { showNewEntry = false })
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            ProfileView()
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .imageScale(.large)
                                .accessibilityLabel("Profile")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewEntry = true } label: {
                            Image(systemName: "plus.circle")
                                .imageScale(.large)
                                .accessibilityLabel("New Entry")
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
            }.tint(.orange)
        } else if entry.status != .done {
            Button { quickStart(entry) } label: {
                Label("Start", systemImage: "play.circle")
            }.tint(.green)
        }
        Button { quickBump(entry, 0.25) } label: { Text("+15m") }.tint(.blue)
        Button { quickBump(entry, 0.5) }  label: { Text("+30m") }.tint(.indigo)
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
            .tint(.orange)
        }
        if entry.status != .inProgress {
            Button {
                entry.status = .inProgress
                if entry.timerStartedAt == nil { entry.timerStartedAt = Date() }
                try? ctx.save()
            } label: {
                Label("In Progress", systemImage: "bolt.fill")
            }
            .tint(Color.brick)
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
            .tint(.green)
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
                if entries.count > cap {
                    Button {
                        withAnimation { toggleExpanded(key) }
                    } label: {
                        HStack {
                            Spacer()
                            Text(expanded ? "Show Less" : "Show All (\(entries.count))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .scaleEffect(iconScale)
                    Text(title)
                }
                    .foregroundStyle(tint)
                    .font(.title3.weight(.semibold))
            }
        }
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

    private var upNextEntries: [Entry] {
        let shown = Set(overdueEntries.map(\.persistentModelID))
            .union(dueTodayEntries.map(\.persistentModelID))
            .union(inProgressEntries.map(\.persistentModelID))
            .union(quickAddEntries.map(\.persistentModelID))

        return openEntries.filter { e in
            guard !shown.contains(e.persistentModelID) else { return false }
            if e.isImportant { return true }
            if let due = e.dueDate, due > todayEnd && due <= weekEnd { return true }
            return false
        }.sorted(by: prioritySort)
    }

    private var backlogEntries: [Entry] {
        let shown = Set(overdueEntries.map(\.persistentModelID))
            .union(dueTodayEntries.map(\.persistentModelID))
            .union(inProgressEntries.map(\.persistentModelID))
            .union(quickAddEntries.map(\.persistentModelID))
            .union(upNextEntries.map(\.persistentModelID))

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

        // Starred
        let starred = allOpen.filter { $0.isImportant }
            .sorted(by: prioritySort)
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

    var body: some View {
        HStack(spacing: 0) {
            DashboardPill(
                icon: "exclamationmark.triangle.fill",
                tint: .red,
                value: "\(overdueCount)",
                label: "Overdue"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "sun.max.fill",
                tint: .orange,
                value: "\(dueTodayCount)",
                label: "Today"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "timer",
                tint: .brick,
                value: "\(timersRunning)",
                label: "Running"
            )
            Divider().frame(height: 36)
            DashboardPill(
                icon: "dollarsign.circle.fill",
                tint: .green,
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

    @State private var tick = Date()

    private var hasRunningTimer: Bool {
        entry.status == .inProgress && entry.timerStartedAt != nil
    }

    private var clientColor: Color {
        entry.client?.accentColor ?? ClientColors.palette[0].color
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(clientColor)
                .frame(width: 4)
                .padding(.vertical, 2)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                // Top line: status dot, client, star, timer/amount
                HStack(spacing: 6) {
                    SharedStatusMark(
                        color: entry.status.color,
                        isImportant: entry.isImportant,
                        pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
                    )

                    Text(entry.clientName)
                        .font(.title3.weight(.semibold))

                if let due = entry.dueDate, badge != .none {
                    dueBadgeView(due: due)
                }

                Spacer()

                if entry.status == .inProgress, entry.timerStartedAt != nil {
                    Text(entry.runningElapsedHoursOrZero.hoursMinutesString)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.brick.opacity(0.15)))
                        .foregroundStyle(Color.brick)
                } else if entry.hours > 0 {
                    Text("\(entry.hours, specifier: "%.1f")h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Bottom line: service, description
            HStack(spacing: 6) {
                Text(entry.service)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.accent)

                if !entry.detail.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(entry.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if entry.status == .done, let completed = entry.completedAt {
                    Text(completed, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            badgePill("Overdue", color: .red)
        case .dueToday:
            badgePill("Today", color: .orange)
        case .dueSoon:
            badgePill(due.formatted(.dateTime.month(.abbreviated).day()), color: .blue)
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    var body: some View {
        Text("\(greeting)\(name.isEmpty ? "" : " \(name)")")
            .font(.title2.weight(.bold))
    }
}

private struct FocusRow: View {
    let index: Int
    let entry: Entry

    private var clientColor: Color {
        entry.client?.accentColor ?? ClientColors.palette[0].color
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(clientColor)
                .frame(width: 4)

            Text("\(index + 1).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.detail.isEmpty ? entry.service : "\(entry.service) — \(entry.detail)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(entry.clientName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
