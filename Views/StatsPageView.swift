import SwiftUI
import SwiftData

struct StatsPageView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @State private var selectedStat: StatsPageSelectedStat? = nil
    @State private var selectedDueList: StatsPageSelectedStat? = nil
    @State private var calendarMonthAnchor: Date = Date()

    var body: some View {
        NavigationStack {
            List {
                // Due buckets
                Section("Due") {
                    HStack {
                        Button {
                            selectedDueList = StatsPageSelectedStat(title: "Due Today", entries: dueToday)
                        } label: {
                            HStack {
                                Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                                Text("Today")
                                Spacer()
                                Text("\(dueToday.count)").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Button {
                            selectedDueList = StatsPageSelectedStat(title: "Due This Week", entries: dueThisWeek)
                        } label: {
                            HStack {
                                Image(systemName: "calendar").foregroundStyle(.accent)
                                Text("This Week")
                                Spacer()
                                Text("\(dueThisWeek.count)").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Button {
                            selectedDueList = StatsPageSelectedStat(title: "Overdue", entries: overdue)
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                                Text("Overdue")
                                Spacer()
                                Text("\(overdue.count)")
                            }
                        }
                    }
                }

                // Calendar (minimal month)
                Section("Calendar") {
                    CalendarMonthView(anchorMonth: calendarMonthAnchor, entries: allEntries)
                        .frame(minHeight: 280)
                }

                Section {
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
                            selectedStat = StatsPageSelectedStat(title: title, entries: entries)
                        },
                        onLoggedTodayTap: {
                            selectedStat = StatsPageSelectedStat(title: "Logged Today", entries: entriesWithLogsToday)
                        }
                    )
                }
            }
            .navigationTitle("Stats")
            .onAppear {
                autoRollOverdueToNextDay()
            }
            .toolbar {
                // ⬅︎ Profile (push)
                ToolbarItem(placement: .topBarLeading) {
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
                    NavigationLink {
                        NewEntryView()
                    } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .accessibilityLabel("New Entry")
                    }
                }
            }
            .sheet(item: $selectedStat) { stat in
                EntriesListView(title: stat.title, entries: stat.entries)
            }
            .sheet(item: $selectedDueList) { stat in
                EntriesListView(title: stat.title, entries: stat.entries)
            }
        }
    }

    // MARK: - Derived (mirrors HomeView)
    private func importantFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant && !rhs.isImportant }
        return lhs.serviceDate > rhs.serviceDate
    }
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

    // MARK: - Due Buckets
    private var effectiveNow: Date { Date() }
    private var todayStart: Date { Calendar.current.startOfDay(for: effectiveNow) }
    private var todayEnd: Date { Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: todayStart) ?? effectiveNow }

    private var dueToday: [Entry] {
        allEntries.filter { e in
            guard e.status != .done, let d = e.dueDate else { return false }
            return d >= todayStart && d <= todayEnd
        }.sorted(by: importantFirst)
    }

    private var dueThisWeek: [Entry] {
        let start = effectiveNow.bdStartOfWeek
        let end = effectiveNow.bdEndOfWeek
        return allEntries.filter { e in
            guard e.status != .done, let d = e.dueDate else { return false }
            return d >= start && d <= end
        }.sorted(by: importantFirst)
    }

    private var overdue: [Entry] {
        let now = effectiveNow
        return allEntries.filter { e in
            guard e.status != .done, let d = e.dueDate else { return false }
            return d < Calendar.current.startOfDay(for: now)
        }.sorted(by: importantFirst)
    }

    // Auto-roll: if due date is before today and not done, move to tomorrow
    private func autoRollOverdueToNextDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var changed = false
        for e in allEntries {
            guard e.status != .done, let d = e.dueDate else { continue }
            if d < today {
                if let next = cal.date(byAdding: .day, value: 1, to: today) {
                    e.dueDate = next
                    changed = true
                }
            }
        }
        if changed { try? ctx.save() }
    }
}

fileprivate struct StatsPageSelectedStat: Identifiable {
    let id = UUID()
    let title: String
    let entries: [Entry]
}

#Preview {
    StatsPageView()
}
