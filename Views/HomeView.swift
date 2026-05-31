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

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Greeting & Today's Focus
                if searchText.isEmpty {
                    Section {
                        GreetingHeader(
                            name: displayName,
                            focusEntries: todayFocusEntries,
                            potentialRevenue: todayFocusRevenue
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
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
                    if !overdueEntries.isEmpty {
                        Section {
                            ForEach(overdueEntries) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: .overdue)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    entrySwipeActions(entry)
                                }
                            }
                        } header: {
                            Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.title3.weight(.semibold))
                        }
                    }

                    // Due Today
                    if !dueTodayEntries.isEmpty {
                        Section {
                            ForEach(dueTodayEntries) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: .dueToday)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    entrySwipeActions(entry)
                                }
                            }
                        } header: {
                            Label("Due Today", systemImage: "sun.max.fill")
                                .foregroundStyle(.orange)
                                .font(.title3.weight(.semibold))
                        }
                    }

                    // In Progress (with timers)
                    if !inProgressEntries.isEmpty {
                        Section {
                            ForEach(inProgressEntries) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: entry.dueDate != nil ? .dueSoon : .none)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    entrySwipeActions(entry)
                                }
                            }
                        } header: {
                            Label("In Progress", systemImage: "bolt.fill")
                                .foregroundStyle(Color.brick)
                                .font(.title3.weight(.semibold))
                        }
                    }

                    // Up Next (starred + due this week, not already shown above)
                    if !upNextEntries.isEmpty {
                        Section {
                            ForEach(upNextEntries) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: dueBadge(for: entry))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    entrySwipeActions(entry)
                                }
                            }
                        } header: {
                            Label("Up Next", systemImage: "arrow.right.circle.fill")
                                .foregroundStyle(.accent)
                                .font(.title3.weight(.semibold))
                        }
                    }

                    // Backlog (remaining to-do with no deadline or deadline > this week)
                    if !backlogEntries.isEmpty {
                        Section {
                            ForEach(backlogEntries) { entry in
                                NavigationLink { EditEntryView(entry: entry) } label: {
                                    ActionRow(entry: entry, badge: .none)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    entrySwipeActions(entry)
                                }
                            }
                        } header: {
                            Label("Backlog", systemImage: "tray.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3.weight(.semibold))
                        }
                    }
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
                NavigationStack {
                    NewEntryView(onSaved: { showNewEntry = false })
                }
                .presentationDetents([.medium, .large])
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
                if sizeClass == .regular {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
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
            }.tint(.orange)
        } else if entry.status != .done {
            Button { quickStart(entry) } label: {
                Label("Start", systemImage: "play.circle")
            }.tint(.green)
        }
        Button { quickBump(entry, 0.25) } label: { Text("+15m") }.tint(.blue)
        Button { quickBump(entry, 0.5) }  label: { Text("+30m") }.tint(.indigo)
        if entry.status != .done {
            Button(role: .destructive) { markDone(entry) } label: {
                Label("Done", systemImage: "checkmark.circle")
            }
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

    private var upNextEntries: [Entry] {
        let shown = Set(overdueEntries.map(\.persistentModelID))
            .union(dueTodayEntries.map(\.persistentModelID))
            .union(inProgressEntries.map(\.persistentModelID))

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

    var body: some View {
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

// MARK: - Greeting Header

private struct GreetingHeader: View {
    let name: String
    let focusEntries: [Entry]
    let potentialRevenue: Double

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Greeting
            Text("\(greeting)\(name.isEmpty ? "" : " \(name)")")
                .font(.title2.weight(.bold))

            if !focusEntries.isEmpty {
                // Today's Focus
                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's Focus")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ForEach(Array(focusEntries.enumerated()), id: \.element.persistentModelID) { index, entry in
                        NavigationLink {
                            EditEntryView(entry: entry)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(focusLabel(for: entry))
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(entry.clientName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Revenue
                HStack {
                    Text("Potential Revenue Today:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(potentialRevenue, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline.weight(.bold))
                }
                .padding(.top, 4)
            }
        }
    }

    private func focusLabel(for entry: Entry) -> String {
        if !entry.detail.isEmpty {
            return "\(entry.service) — \(entry.detail)"
        }
        return entry.service
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
