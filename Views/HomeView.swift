import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]

    // Section states
    @AppStorage("home.showStarred") private var showStarred = true
    @AppStorage("home.showTodo") private var showTodo = false
    @AppStorage("home.showInProgress") private var showInProgress = false
    @AppStorage("home.showAllDone") private var showAllDone = false
    @AppStorage("home.showDone") private var showDone = false
    @AppStorage("home.showStats") private var showStats = false
    @AppStorage("home.showRecent") private var showRecent = false
    @AppStorage("home.recentCount") private var recentCount: Int = 10

    // UI state
    @State private var showNewEntry = false
    @State private var selectedStat: SelectedStat? = nil

    var body: some View {
        NavigationStack {
            List {
                // Quick: New Entry
                Section {
                    Button { showNewEntry = true } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New Entry").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // ⭐️ Starred
                Section {
                    DisclosureGroup(isExpanded: $showStarred) {
                        let starred = starredEntries
                        if starred.isEmpty {
                            Text("No starred items").foregroundStyle(.secondary)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        } else {
                            ForEach(starred) { e in
                                NavigationLink { EditEntryView(entry: e) } label: {
                                    if e.status == .inProgress {
                                        SharedInProgressRow(entry: e)
                                    } else {
                                        SharedTodoRow(entry: e)
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            }
                        }
                    } label: {
                        SectionHeaderLabel(icon: "star.fill", title: "Starred", tint: .yellow, count: starredEntries.count)
                    }
                }

                // To Do
                Section {
                    DisclosureGroup(isExpanded: $showTodo) {
                        let items = todoEntries
                        if items.isEmpty {
                            Text("No to-do items").foregroundStyle(.secondary)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        } else {
                            ForEach(items) { e in
                                NavigationLink { EditEntryView(entry: e) } label: {
                                    SharedTodoRow(entry: e)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            }
                        }
                    } label: {
                        SectionHeaderLabel(icon: "checklist", title: "To Do", tint: .orange, count: todoEntries.count)
                    }
                }

                // In Progress
                Section {
                    DisclosureGroup(isExpanded: $showInProgress) {
                        let active = inProgressEntries
                        if active.isEmpty {
                            Text("No in-progress items").foregroundStyle(.secondary)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        } else {
                            ForEach(active) { e in
                                NavigationLink { EditEntryView(entry: e) } label: {
                                    SharedInProgressRow(entry: e)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if e.timerStartedAt != nil {
                                        Button { quickPauseAndAdd(e) } label: {
                                            Label("Pause & Add", systemImage: "pause.circle")
                                        }.tint(.orange)
                                    } else {
                                        Button { quickStart(e) } label: {
                                            Label("Start", systemImage: "play.circle")
                                        }.tint(.green)
                                    }
                                    Button { quickBump(e, 0.25) } label: { Text("+15m") }.tint(.blue)
                                    Button { quickBump(e, 0.5) }  label: { Text("+30m") }.tint(.indigo)
                                    Button { quickBump(e, 1.0) }  label: { Text("+1h") }.tint(.purple)
                                    Button(role: .destructive) { markDone(e) } label: {
                                        Label("Done", systemImage: "checkmark.circle")
                                    }
                                }
                            }
                        }
                    } label: {
                        SectionHeaderLabel(icon: "bolt.fill", title: "In Progress", tint: .brick, count: inProgressEntries.count)
                    }
                }

                // Done
                Section {
                    DisclosureGroup(isExpanded: $showDone) {
                        let items = doneEntries
                        let displayed = showAllDone ? items : Array(items.prefix(20))
                        if items.isEmpty {
                            Text("No done items").foregroundStyle(.secondary)
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        } else {
                            ForEach(displayed) { e in
                                NavigationLink { EditEntryView(entry: e) } label: {
                                    SharedDoneRow(entry: e)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            }
                            if items.count > 20 {
                                Button(action: { withAnimation { showAllDone.toggle() } }) {
                                    HStack {
                                        Spacer()
                                        Text(showAllDone ? "Show Less" : "Show All (\(items.count))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                            }
                        }
                    } label: {
                        SectionHeaderLabel(icon: "checkmark.circle.fill", title: "Done", tint: .green, count: doneEntries.count)
                    }
                }

                /*
                // Stats
                Section {
                    DisclosureGroup(isExpanded: $showStats) {
                        StatsSectionView(
                            today: todayEntries,
                            week: thisWeekEntries,
                            lastWeek: lastWeekEntries,
                            month: thisMonthEntries,
                            lastMonth: lastMonthEntries,
                            quarter: thisQuarterEntries,
                            yearToDate: yearToDateEntries,
                            loggedTodayHours: totalHoursLoggedToday,
                            entriesWithLogsToday: entriesWithLogsToday,
                            loggedTodayAmount: loggedTodayAmount,
                            onStatTap: { title, entries in
                                selectedStat = SelectedStat(title: title, entries: entries)
                            },
                            onLoggedTodayTap: {
                                selectedStat = SelectedStat(title: "Logged Today", entries: entriesWithLogsToday)
                            }
                        )
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: 10) {
                            ZstackIcon(systemImage: "chart.bar.fill")
                            Text("Stats")
                            Spacer()
                        }
                    }
                }
                */

                // Recent
                Section {
                    DisclosureGroup(isExpanded: $showRecent) {
                        if recentEntries.isEmpty {
                            Text("No recent entries").foregroundStyle(.secondary)
                        } else {
                            ForEach(recentEntries) { e in
                                NavigationLink { EditEntryView(entry: e) } label: {
                                    SharedEntryRow(entry: e)
                                }
                            }
                        }
                    } label: {
                        SectionHeaderLabel(icon: "clock.fill", title: "Recent", tint: .indigo, count: recentEntries.count)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listRowSpacing(6)
            .navigationTitle("Ohno Design")
            .sheet(isPresented: $showNewEntry) {
                NavigationStack {
                    NewEntryView(onSaved: { showNewEntry = false })
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedStat) { stat in
                EntriesListView(title: stat.title, entries: stat.entries)
            }
            .toolbar {
                // ⬅︎ Profile (push)
                ToolbarItem(placement: .topBarLeading) {    // use .navigationBarLeading for iOS 16
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .imageScale(.large)
                            .accessibilityLabel("Profile")
                    }
                }
                // ➝ New Entry
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

    // MARK: - Quick actions
    private func quickStart(_ e: Entry) {
        e.status = .inProgress
        if e.timerStartedAt == nil { e.timerStartedAt = Date() }
        try? ctx.save()
    }
    private func quickPauseAndAdd(_ e: Entry) {
        guard e.timerStartedAt != nil else { return }
        e.hours += e.runningElapsedHoursOrZero
        e.timeLogs.append(TimeLog(hours: e.runningElapsedHoursOrZero, entry: e))
        e.timerStartedAt = nil
        try? ctx.save()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogs.append(TimeLog(hours: h, entry: e))
        try? ctx.save()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        try? ctx.save()
    }

    // MARK: - Derived
    private func importantFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant && !rhs.isImportant }
        return lhs.serviceDate > rhs.serviceDate
    }
    private var starredEntries: [Entry] { allEntries.filter { $0.isImportant && ($0.status == .todo || $0.status == .inProgress) }.sorted(by: importantFirst) }
    private var todoEntries: [Entry] { allEntries.filter { $0.status == .todo }.sorted(by: importantFirst) }
    private var inProgressEntries: [Entry] { allEntries.filter { $0.status == .inProgress }.sorted(by: importantFirst) }
    private var doneEntries: [Entry] { allEntries.filter { $0.status == .done }.sorted { $0.serviceDate > $1.serviceDate } }
    private var recentEntries: [Entry] { Array(allEntries.sorted(by: importantFirst).prefix(max(0, recentCount))) }
    private var todayEntries: [Entry] { allEntries.filter { $0.status == .done && Calendar.current.isDateInToday(($0.completedAt ?? $0.serviceDate)) } }

    private var timeLogsTodayByEntry: [(entry: Entry, hours: Double)] {
        let todayLogs = allEntries.flatMap { e in e.timeLogs.map { ($0, e) } }
            .filter { Calendar.current.isDateInToday($0.0.addedAt) }
        let grouped = Dictionary(grouping: todayLogs, by: { $0.1.persistentModelID })
        return grouped.compactMap { (_, pairs) in
            guard let any = pairs.first?.1 else { return nil }
            let sum = pairs.reduce(0.0) { $0 + $1.0.hours }
            return (entry: any, hours: sum)
        }
        .sorted { $0.entry.serviceDate > $1.entry.serviceDate }
    }
    private var entriesWithLogsToday: [Entry] { timeLogsTodayByEntry.map { $0.entry } }
    private var totalHoursLoggedToday: Double { timeLogsTodayByEntry.reduce(0.0) { $0 + $1.hours } }
    private var loggedTodayAmount: Double {
        // Sum per-entry: (today hours for that entry) * entry.rate
        timeLogsTodayByEntry.reduce(0.0) { $0 + ($1.hours * $1.entry.rate) }
    }

    private var thisWeekEntries: [Entry] {
        let now = Date(); let start = now.bdStartOfWeek; let end = now.bdEndOfWeek
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= start && d <= end }
    }
    private var lastWeekEntries: [Entry] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .weekOfYear, value: -1, to: Date())?.bdStartOfWeek,
              let end   = cal.date(byAdding: .weekOfYear, value: -1, to: Date())?.bdEndOfWeek else { return [] }
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= start && d <= end }
    }
    private var thisMonthEntries: [Entry] {
        let now = Date(); let start = now.bdStartOfMonth; let end = now.bdEndOfMonth
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= start && d <= end }
    }
    private var lastMonthEntries: [Entry] {
        let cal = Calendar.current; guard let prev = cal.date(byAdding: .month, value: -1, to: Date()) else { return [] }
        let start = prev.bdStartOfMonth; let end = prev.bdEndOfMonth
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= start && d <= end }
    }
    private var thisQuarterEntries: [Entry] {
        let now = Date(); let b = now.bdQuarterBounds
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= b.start && d <= b.end }
    }
    private var yearToDateEntries: [Entry] {
        let cal = Calendar.current; let now = Date()
        let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        return allEntries.filter { e in let d = (e.completedAt ?? e.serviceDate); return e.status == .done && d >= startOfYear && d <= now }
    }
}

// MARK: - SelectedStat
private struct SelectedStat: Identifiable {
    let id = UUID()
    let title: String
    let entries: [Entry]
}

// MARK: - Helpers
private struct ZstackIcon: View {
    let systemImage: String
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
        }
        .frame(width: 24, height: 24)
    }
}

private struct SectionHeaderLabel: View {
    let icon: String
    let title: String
    let tint: Color
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon).foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)
            Text(title)
            Spacer()
            Text("\(count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

private struct LoggedTodayEntryRow: View {
    let entry: Entry

    private var todayHours: Double {
        entry.timeLogs.filter { Calendar.current.isDateInToday($0.addedAt) }
            .reduce(0.0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SharedStatusMark(
                    color: entry.status.color,
                    isImportant: entry.isImportant,
                    pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
                )
                Text(entry.client.name).font(.headline)
                Spacer()
                // Show today's subtotal amount for this entry
                let amount = todayHours * entry.rate
                Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(entry.service); Text("•")
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                Spacer()
                Text("Today: \(todayHours, specifier: "%.2f")h")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
