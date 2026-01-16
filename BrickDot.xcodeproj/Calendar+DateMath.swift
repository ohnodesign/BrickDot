import Foundation

extension Calendar {
    /// Returns the number of whole months between two dates, considering only the year and month components.
    /// Positive if `end` is after `start`, negative if `end` is before `start`.
    func monthsBetween(_ start: Date, _ end: Date) -> Int {
        let startComps = dateComponents([.year, .month], from: start)
        let endComps = dateComponents([.year, .month], from: end)
        guard let sy = startComps.year, let sm = startComps.month,
              let ey = endComps.year, let em = endComps.month else {
            return 0
        }
        return (ey - sy) * 12 + (em - sm)
    }

    /// Convenience label form of `monthsBetween`.
    func monthsBetween(from start: Date, to end: Date) -> Int {
        return monthsBetween(start, end)
    }

    /// Returns an array of month anchor dates between the two dates (inclusive), using the calendar's year/month components.
    /// Each returned date is normalized to the first day of its month.
    func monthsBetween(start: Date, end: Date) -> [Date] {
        let cal = self
        // Normalize both dates to the first day of their months
        let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) ?? end

        var months: [Date] = []
        if startMonth <= endMonth {
            var current = startMonth
            while current <= endMonth {
                months.append(current)
                guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
                current = next
            }
        } else {
            var current = endMonth
            while current <= startMonth {
                months.append(current)
                guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
                current = next
            }
            months.reverse()
        }
        return months
    }

    /// Static labeled overload returning month anchors between two dates (inclusive).
    static func monthsBetween(start: Date, end: Date) -> [Date] {
        Calendar.current.monthsBetween(start: start, end: end)
    }
}
