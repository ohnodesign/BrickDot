import Foundation

extension Date {
    /// Start of the week for the current date, using the user's current Calendar and locale.
    var bdStartOfWeek: Date {
        let cal = Calendar.current
        if let start = cal.dateInterval(of: .weekOfYear, for: self)?.start {
            return start
        }
        return self
    }

    /// End of the week for the current date (inclusive), computed as one second before the start of next week.
    var bdEndOfWeek: Date {
        let cal = Calendar.current
        if let weekStart = cal.dateInterval(of: .weekOfYear, for: self)?.start,
           let nextWeekStart = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart),
           let inclusiveEnd = cal.date(byAdding: .second, value: -1, to: nextWeekStart) {
            return inclusiveEnd
        }
        return self
    }

    /// Bounds of the quarter containing the current date. The end is inclusive (last moment before the next quarter begins).
    var bdQuarterBounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        guard let year = comps.year, let month = comps.month else { return (self, self) }

        // Determine the first month of the quarter (1-based months)
        let quarterIndex = (month - 1) / 3 // 0 for Jan-Mar, 1 for Apr-Jun, etc.
        let startMonth = quarterIndex * 3 + 1

        // Start is the first day of the first month of the quarter at start of day
        guard let start = cal.date(from: DateComponents(year: year, month: startMonth, day: 1)) else {
            return (self, self)
        }

        // Compute the start of the next quarter, then subtract 1 second for an inclusive end
        let nextQuarterStart: Date
        if let nq = cal.date(byAdding: .month, value: 3, to: start) {
            nextQuarterStart = nq
        } else {
            nextQuarterStart = start
        }
        let inclusiveEnd = cal.date(byAdding: .second, value: -1, to: nextQuarterStart) ?? start

        return (start, inclusiveEnd)
    }
    
    /// Start of the month for the current date, using the user's current Calendar.
    var bdStartOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }

    /// End of the month for the current date (inclusive), computed as one second before the next month begins.
    var bdEndOfMonth: Date {
        let cal = Calendar.current
        if let start = cal.date(from: cal.dateComponents([.year, .month], from: self)),
           let nextMonthStart = cal.date(byAdding: .month, value: 1, to: start),
           let inclusiveEnd = cal.date(byAdding: .second, value: -1, to: nextMonthStart) {
            return inclusiveEnd
        }
        return self
    }
}
