import SwiftUI
import SwiftData

public struct CalendarMonthView: View {
    let anchorMonth: Date
    let entries: [Entry]

    @State private var selectedDay: IdentifiableDate?

    private struct IdentifiableDate: Identifiable {
        let id: Date
        var date: Date { id }
    }

    private let calendar = Calendar.current

    private var monthStart: Date {
        anchorMonth.startOfMonth(in: calendar)
    }

    private var monthEnd: Date {
        anchorMonth.endOfMonth(in: calendar)
    }

    private var daysInMonth: [Date] {
        var days: [Date] = []
        var current = monthStart
        while current <= monthEnd {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    private var weekdaySymbols: [String] {
        calendar.veryShortStandaloneWeekdaySymbols
    }

    private func dueCount(for day: Date) -> Int {
        dueEntries(for: day).count
    }

    private func dueEntries(for day: Date) -> [Entry] {
        let dayStart = day.startOfDay(in: calendar)
        let dayEnd = day.endOfDay(in: calendar)
        return entries.filter { entry in
            guard entry.status != .done else { return false }
            let relevantDate = entry.dueDate ?? entry.serviceDate
            return relevantDate >= dayStart && relevantDate <= dayEnd
        }
    }

    private var firstWeekdayIndex: Int {
        // index of first day of month in the weekdaySymbols array (0-based)
        // calendar.weekday: 1=Sunday ... 7=Saturday
        let weekday = calendar.component(.weekday, from: monthStart)
        return weekday - 1
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid with padding for first weekday offset
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                // Padding before first day
                ForEach(0..<firstWeekdayIndex, id: \.self) { _ in
                    Color.clear.frame(height: 32)
                }

                ForEach(daysInMonth, id: \.self) { day in
                    let count = dueCount(for: day)
                    let isToday = calendar.isDateInToday(day)
                    Button {
                        selectedDay = IdentifiableDate(id: day)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Text("\(calendar.component(.day, from: day))")
                                .frame(maxWidth: .infinity, maxHeight: 32)
                                .foregroundColor(isToday ? .primary : .primary)
                                .contentShape(Rectangle())

                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Circle().fill(Color.red))
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .padding(.vertical, 4)
                        .overlay {
                            if isToday {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .sheet(item: $selectedDay) { item in
            NavigationStack {
                let dayEntries = dueEntries(for: item.date)
                List(dayEntries, id: \.persistentModelID) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.service)
                            .font(.headline)
                        if !entry.detail.isEmpty {
                            Text(entry.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Due on \(formattedDate(item.date))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            selectedDay = nil
                        }
                    }
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

fileprivate extension Date {
    func startOfMonth(in calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: self))!
    }

    func endOfMonth(in calendar: Calendar) -> Date {
        let startNextMonth = calendar.date(byAdding: DateComponents(month: 1), to: startOfMonth(in: calendar))!
        return calendar.date(byAdding: DateComponents(day: -1), to: startNextMonth)!
    }

    func startOfDay(in calendar: Calendar) -> Date {
        calendar.startOfDay(for: self)
    }

    func endOfDay(in calendar: Calendar) -> Date {
        let start = startOfDay(in: calendar)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
    }
}

#Preview {
    CalendarMonthView(anchorMonth: Date(), entries: [])
}
