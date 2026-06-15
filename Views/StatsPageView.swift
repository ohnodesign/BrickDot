import SwiftUI
import SwiftData
import Charts

struct StatsPageView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @State private var selectedStat: StatsPageSelectedStat? = nil
    @State private var selectedDueList: StatsPageSelectedStat? = nil
    @State private var calendarMonthAnchor: Date = Date()
    @State private var reportPeriod: ReportPeriod = .last12Weeks

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
                                Image(systemName: "sun.max.fill").foregroundStyle(theme.dueToday)
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
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.overdue)
                                Text("Overdue")
                                Spacer()
                                Text("\(overdue.count)")
                            }
                        }
                    }
                }

                // Status counts
                Section {
                    HStack(spacing: 0) {
                        Button {
                            selectedStat = StatsPageSelectedStat(title: "To Do", entries: todoEntries)
                        } label: {
                            StatusCountPill(icon: "circle", label: "To Do", count: todoCount, tint: theme.dueToday)
                        }.buttonStyle(.plain)
                        Divider().frame(height: 36)
                        Button {
                            selectedStat = StatsPageSelectedStat(title: "In Progress", entries: inProgressEntriesList)
                        } label: {
                            StatusCountPill(icon: "bolt.fill", label: "In Progress", count: inProgressCount, tint: theme.running)
                        }.buttonStyle(.plain)
                        Divider().frame(height: 36)
                        Button {
                            selectedStat = StatsPageSelectedStat(title: "Starred", entries: starredEntries)
                        } label: {
                            StatusCountPill(icon: "star.fill", label: "Starred", count: starredCount, tint: .yellow)
                        }.buttonStyle(.plain)
                    }
                }

                // Calendar (minimal month)
                Section("Calendar") {
                    CalendarMonthView(anchorMonth: calendarMonthAnchor, entries: allEntries)
                        .frame(minHeight: 280)
                }

                // Charts
                Section {
                    HStack {
                        Text("Reports")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        ReportPeriodPicker(selection: $reportPeriod)
                    }
                    RevenueChartView(entries: allEntries, period: reportPeriod)
                        .padding(.vertical, 8)
                }

                Section {
                    ClientProfitabilityChartView(entries: allEntries, period: reportPeriod)
                        .padding(.vertical, 8)
                }

                Section {
                    ServiceHoursChartView(entries: allEntries, period: reportPeriod)
                        .padding(.vertical, 8)
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
            .sheet(item: $selectedStat) { stat in
                EntriesListView(title: stat.title, entries: stat.entries)
            }
            .sheet(item: $selectedDueList) { stat in
                EntriesListView(title: stat.title, entries: stat.entries)
            }
        }
    }

    // MARK: - Status Counts
    private var todoEntries: [Entry] { allEntries.filter { $0.status == .todo } }
    private var todoCount: Int { todoEntries.count }
    private var inProgressEntriesList: [Entry] { allEntries.filter { $0.status == .inProgress } }
    private var inProgressCount: Int { inProgressEntriesList.count }
    private var starredEntries: [Entry] { allEntries.filter { $0.isImportant && $0.status != .done } }
    private var starredCount: Int { starredEntries.count }

    // MARK: - Derived (mirrors HomeView)
    private func importantFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.isImportant != rhs.isImportant { return lhs.isImportant && !rhs.isImportant }
        return lhs.serviceDate > rhs.serviceDate
    }
    private var todayEntries: [Entry] { allEntries.filter { $0.status == .done && Calendar.current.isDateInToday(($0.completedAt ?? $0.serviceDate)) } }

    private var timeLogsTodayByEntry: [(entry: Entry, hours: Double)] {
        let todayLogs = allEntries.flatMap { e in e.timeLogsList.map { ($0, e) } }
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
            guard e.status != .done, let due = e.dueDate else { return false }
            return due >= todayStart && due <= todayEnd
        }.sorted(by: importantFirst)
    }

    private var dueThisWeek: [Entry] {
        let start = effectiveNow.bdStartOfWeek
        let end = effectiveNow.bdEndOfWeek
        return allEntries.filter { e in
            guard e.status != .done, let due = e.dueDate else { return false }
            return due >= start && due <= end
        }.sorted(by: importantFirst)
    }

    private var overdue: [Entry] {
        return allEntries.filter { e in
            guard e.status != .done, let due = e.dueDate else { return false }
            return due < todayStart
        }.sorted(by: importantFirst)
    }
}

fileprivate struct StatsPageSelectedStat: Identifiable {
    let id = UUID()
    let title: String
    let entries: [Entry]
}

private struct StatusCountPill: View {
    let icon: String
    let label: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text("\(count)")
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

#Preview {
    StatsPageView()
}
