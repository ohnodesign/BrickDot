import SwiftUI
import Charts

// MARK: - Report Period

enum ReportPeriod: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case yearToDate = "Year to Date"
    case last12Weeks = "Last 12 Weeks"
    case allTime = "All Time"

    var id: String { rawValue }

    var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisWeek:
            return (now.bdStartOfWeek, now.bdEndOfWeek)
        case .thisMonth:
            return (now.startOfMonth, now.endOfMonth)
        case .lastMonth:
            guard let prev = cal.date(byAdding: .month, value: -1, to: now) else { return (now, now) }
            return (prev.startOfMonth, prev.endOfMonth)
        case .thisQuarter:
            let b = now.bdQuarterBounds
            return (b.start, b.end)
        case .yearToDate:
            let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return (startOfYear, now)
        case .last12Weeks:
            let start = cal.date(byAdding: .weekOfYear, value: -11, to: now)?.bdStartOfWeek ?? now
            return (start, now)
        case .allTime:
            return (Date.distantPast, now)
        }
    }

    func filter(_ entries: [Entry]) -> [Entry] {
        let range = dateRange
        return entries.filter { e in
            guard e.status == .done else { return false }
            let d = e.completedAt ?? e.serviceDate
            return d >= range.start && d <= range.end
        }
    }
}

// MARK: - Period Picker

struct ReportPeriodPicker: View {
    @Binding var selection: ReportPeriod

    var body: some View {
        Menu {
            ForEach(ReportPeriod.allCases) { period in
                Button {
                    selection = period
                } label: {
                    HStack {
                        Text(period.rawValue)
                        if period == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.rawValue)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.accent)
        }
    }
}

// MARK: - Revenue Over Time

struct RevenueChartView: View {
    let entries: [Entry]
    let period: ReportPeriod
    @Environment(\.appTheme) private var theme

    private struct TimeBucket: Identifiable {
        let id: Date
        let label: String
        let amount: Double
    }

    private enum BucketSize {
        case daily, weekly, monthly
    }

    private var bucketSize: BucketSize {
        switch period {
        case .thisWeek: return .daily
        case .thisMonth, .lastMonth, .last12Weeks: return .weekly
        case .thisQuarter, .yearToDate, .allTime: return .monthly
        }
    }

    private var filteredEntries: [Entry] {
        period.filter(entries)
    }

    private var totalRevenue: Double {
        filteredEntries.reduce(0) { $0 + ($1.hours * $1.rate) }
    }

    private var bucketData: [TimeBucket] {
        let cal = Calendar.current
        let range = period.dateRange
        let done = filteredEntries

        switch bucketSize {
        case .daily:
            return buildDailyBuckets(cal: cal, range: range, entries: done)
        case .weekly:
            return buildWeeklyBuckets(cal: cal, range: range, entries: done)
        case .monthly:
            return buildMonthlyBuckets(cal: cal, range: range, entries: done)
        }
    }

    private func buildDailyBuckets(cal: Calendar, range: (start: Date, end: Date), entries: [Entry]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        let df = DateFormatter()
        df.dateFormat = "E"
        var day = cal.startOfDay(for: range.start)
        while day <= range.end {
            let dayEnd = day.endOfDay
            let amount = entries.filter { e in
                let d = e.completedAt ?? e.serviceDate
                return d >= day && d <= dayEnd
            }.reduce(0.0) { $0 + ($1.hours * $1.rate) }
            buckets.append(TimeBucket(id: day, label: df.string(from: day), amount: amount))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return buckets
    }

    private func buildWeeklyBuckets(cal: Calendar, range: (start: Date, end: Date), entries: [Entry]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        let df = DateFormatter()
        df.dateFormat = "M/d"
        var weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: range.start)) ?? range.start
        while weekStart <= range.end {
            guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { break }
            let amount = entries.filter { e in
                let d = e.completedAt ?? e.serviceDate
                return d >= weekStart && d <= weekEnd.endOfDay
            }.reduce(0.0) { $0 + ($1.hours * $1.rate) }
            buckets.append(TimeBucket(id: weekStart, label: df.string(from: weekStart), amount: amount))
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return buckets
    }

    private func buildMonthlyBuckets(cal: Calendar, range: (start: Date, end: Date), entries: [Entry]) -> [TimeBucket] {
        var buckets: [TimeBucket] = []
        let df = DateFormatter()
        df.dateFormat = "MMM"
        var monthStart = cal.date(from: cal.dateComponents([.year, .month], from: range.start)) ?? range.start
        while monthStart <= range.end {
            let monthEnd = monthStart.endOfMonth
            let amount = entries.filter { e in
                let d = e.completedAt ?? e.serviceDate
                return d >= monthStart && d <= monthEnd
            }.reduce(0.0) { $0 + ($1.hours * $1.rate) }
            buckets.append(TimeBucket(id: monthStart, label: df.string(from: monthStart), amount: amount))
            guard let next = cal.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }
        return buckets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Revenue")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(totalRevenue.shortCurrency)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.revenue)
            }

            if bucketData.allSatisfy({ $0.amount == 0 }) {
                Text("No completed billable work in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(bucketData) { bucket in
                    BarMark(
                        x: .value("Period", bucket.label),
                        y: .value("Revenue", bucket.amount)
                    )
                    .foregroundStyle(theme.revenue.gradient)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.shortCurrency)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Client Profitability (horizontal bar chart)

struct ClientProfitabilityChartView: View {
    let entries: [Entry]
    let period: ReportPeriod
    @Environment(\.appTheme) private var theme

    private struct ClientRevenue: Identifiable {
        let id: String
        let name: String
        let amount: Double
        let hours: Double
        let color: Color
    }

    private var clientData: [ClientRevenue] {
        let done = period.filter(entries)
        var grouped: [String: (amount: Double, hours: Double, color: Color)] = [:]

        for e in done {
            let name = e.clientName
            let existing = grouped[name] ?? (0, 0, e.client?.accentColor ?? .gray)
            grouped[name] = (existing.amount + e.hours * e.rate, existing.hours + e.hours, existing.color)
        }

        return grouped.map { ClientRevenue(id: $0.key, name: $0.key, amount: $0.value.amount, hours: $0.value.hours, color: $0.value.color) }
            .sorted { $0.amount > $1.amount }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Client Profitability")
                .font(.subheadline.weight(.semibold))

            if clientData.isEmpty {
                Text("No completed work in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(clientData) { client in
                    BarMark(
                        x: .value("Revenue", client.amount),
                        y: .value("Client", client.name)
                    )
                    .foregroundStyle(client.color.gradient)
                    .cornerRadius(3)
                    .annotation(position: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(client.amount.shortCurrency)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                            Text(String(format: "%.1fh", client.hours))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption)
                    }
                }
                .frame(height: max(CGFloat(clientData.count) * 36, 80))
            }
        }
    }
}

// MARK: - Hours by Service Type (donut chart)

struct ServiceHoursChartView: View {
    let entries: [Entry]
    let period: ReportPeriod
    @Environment(\.appTheme) private var theme

    private struct ServiceSlice: Identifiable {
        let id: String
        let service: String
        let hours: Double
        let color: Color
    }

    private static let sliceColors: [Color] = [
        Color(hex: "2563EB"),
        Color(hex: "16A34A"),
        Color(hex: "EA580C"),
        Color(hex: "7C3AED"),
        Color(hex: "DC2626"),
        Color(hex: "0891B2"),
        Color(hex: "CA8A04"),
        Color(hex: "DB2777"),
    ]

    private var serviceData: [ServiceSlice] {
        let done = period.filter(entries).filter { $0.hours > 0 }
        var grouped: [String: Double] = [:]

        for e in done {
            let key = e.service.uppercased()
            grouped[key, default: 0] += e.hours
        }

        let sorted = grouped.sorted { $0.value > $1.value }
        return sorted.enumerated().map { i, pair in
            ServiceSlice(
                id: pair.key,
                service: pair.key,
                hours: pair.value,
                color: Self.sliceColors[i % Self.sliceColors.count]
            )
        }
    }

    private var totalHours: Double {
        serviceData.reduce(0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hours by Service")
                .font(.subheadline.weight(.semibold))

            if serviceData.isEmpty {
                Text("No logged hours in this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Chart(serviceData) { slice in
                        SectorMark(
                            angle: .value("Hours", slice.hours),
                            innerRadius: .ratio(0.6),
                            angularInset: 1.5
                        )
                        .foregroundStyle(slice.color)
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)
                    .overlay {
                        VStack(spacing: 2) {
                            Text(String(format: "%g", totalHours))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text("hours")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(serviceData) { slice in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 8, height: 8)
                                Text(slice.service)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%gh", slice.hours))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
            }
        }
    }
}
