import Foundation

extension Date {
    var bdStartOfWeek: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? self
    }
    var bdEndOfWeek: Date {
        let cal = Calendar.current
        let start = bdStartOfWeek
        return cal.date(byAdding: .day, value: 6, to: start)?.bdEndOfDay ?? self
    }
    var bdEndOfDay: Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: self)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? self
    }
    var bdQuarterBounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        guard let year = comps.year, let month = comps.month else { return (self, self) }
        let q = (month - 1) / 3
        let startMonth = q * 3 + 1
        let endMonth = startMonth + 2
        let start = cal.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? self
        let end = cal.date(from: DateComponents(year: year, month: endMonth + 1, day: 1, second: -1)) ?? self
        return (start, end)
    }
    var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? self
    }
    var endOfMonth: Date {
        let cal = Calendar.current
        if let start = cal.date(from: cal.dateComponents([.year, .month], from: self)),
           let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) {
            return end
        }
        return self
    }
}
