import SwiftUI
import Charts

// MARK: - Revenue Over Time (weekly bar chart, last 12 weeks)

struct RevenueChartView: View {
    let entries: [Entry]
    @Environment(\.appTheme) private var theme

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    private struct WeekBucket: Identifiable {
        let id: Date
        let label: String
        let amount: Double
    }

    private var weeklyData: [WeekBucket] {
        let cal = Calendar.current
        let today = Date()
        var buckets: [WeekBucket] = []

        for weeksAgo in (0..<12).reversed() {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksAgo, to: today) else { continue }
            let start = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
            guard let bucketStart = cal.date(from: start),
                  let bucketEnd = cal.date(byAdding: .day, value: 6, to: bucketStart) else { continue }

            let amount = entries
                .filter { e in
                    guard e.status == .done else { return false }
                    let d = e.completedAt ?? e.serviceDate
                    return d >= bucketStart && d <= bucketEnd.endOfDay
                }
                .reduce(0.0) { $0 + ($1.hours * $1.rate) }

            let df = DateFormatter()
            df.dateFormat = "M/d"
            buckets.append(WeekBucket(id: bucketStart, label: df.string(from: bucketStart), amount: amount))
        }
        return buckets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Revenue — Last 12 Weeks")
                .font(.subheadline.weight(.semibold))

            if weeklyData.allSatisfy({ $0.amount == 0 }) {
                Text("No completed billable work yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(weeklyData) { bucket in
                    BarMark(
                        x: .value("Week", bucket.label),
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
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
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
    @Environment(\.appTheme) private var theme

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    private struct ClientRevenue: Identifiable {
        let id: String
        let name: String
        let amount: Double
        let hours: Double
        let color: Color
    }

    private var clientData: [ClientRevenue] {
        let done = entries.filter { $0.status == .done }
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
                Text("No completed work yet.")
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
                        Text(client.amount.shortCurrency)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
        let done = entries.filter { $0.status == .done && $0.hours > 0 }
        var grouped: [String: Double] = [:]

        for e in done {
            grouped[e.service, default: 0] += e.hours
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
                Text("No logged hours yet.")
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
