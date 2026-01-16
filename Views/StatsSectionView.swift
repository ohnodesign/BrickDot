import SwiftUI

struct StatsSectionView: View {
    let today: [Entry]
    let week: [Entry]
    let lastWeek: [Entry]
    let month: [Entry]
    let lastMonth: [Entry]
    let quarter: [Entry]
    let yearToDate: [Entry]

    let loggedTodayHours: Double
    let entriesWithLogsToday: [Entry]
    let loggedTodayAmount: Double

    let onStatTap: (String, [Entry]) -> Void
    let onLoggedTodayTap: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            Button {
                onStatTap("Completed Today", today)
            } label: {
                SharedStatPill(title: "Completed Today", entries: today, icon: "sun.max.fill")
            }
            .buttonStyle(.plain)

            Button {
                onLoggedTodayTap()
            } label: {
                LoggedTodayPill(hours: loggedTodayHours, count: entriesWithLogsToday.count, amount: loggedTodayAmount)
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("This Week", week)
            } label: {
                SharedStatPill(title: "This Week", entries: week, icon: "calendar")
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("Last Week", lastWeek)
            } label: {
                SharedStatPill(title: "Last Week", entries: lastWeek, icon: "calendar")
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("This Month", month)
            } label: {
                SharedStatPill(title: "This Month", entries: month, icon: "calendar.badge.clock")
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("Last Month", lastMonth)
            } label: {
                SharedStatPill(title: "Last Month", entries: lastMonth, icon: "calendar.badge.clock")
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("This Quarter", quarter)
            } label: {
                SharedStatPill(title: "This Quarter", entries: quarter, icon: "calendar.badge.exclamationmark")
            }
            .buttonStyle(.plain)

            Button {
                onStatTap("Year to Date", yearToDate)
            } label: {
                SharedStatPill(title: "Year to Date", entries: yearToDate, icon: "calendar.badge.plus")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    StatsSectionView(
        today: [],
        week: [],
        lastWeek: [],
        month: [],
        lastMonth: [],
        quarter: [],
        yearToDate: [],
        loggedTodayHours: 0,
        entriesWithLogsToday: [],
        loggedTodayAmount: 0,
        onStatTap: { _, _ in },
        onLoggedTodayTap: {}
    )
}
