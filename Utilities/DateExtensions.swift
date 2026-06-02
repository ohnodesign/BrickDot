import Foundation

extension Date {
    var startOfMonth: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }

    var endOfMonth: Date {
        let cal = Calendar.current
        guard let startNext = cal.date(byAdding: DateComponents(month: 1), to: startOfMonth) else { return self }
        return cal.date(byAdding: .second, value: -1, to: startNext) ?? self
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }

    var yearMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: self)
    }

    var yearMonthDay: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
