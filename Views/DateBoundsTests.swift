#if canImport(Testing)
import Testing
@testable import BrickDot

@Suite("Date Bounds Helpers")
struct DateBoundsTests {

    @Test("Month start/end are consistent and inclusive")
    func monthBounds() {
        let cal = Calendar(identifier: .gregorian)
        var comps = DateComponents(year: 2025, month: 3, day: 15)
        let date = cal.date(from: comps)!

        let start = date.bdStartOfMonth
        let end   = date.bdEndOfMonth

        // Start should be March 1, 2025 at 00:00
        comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        let expectedStart = cal.date(from: comps)!
        #expect(cal.isDate(start, inSameDayAs: expectedStart))

        // End should be inclusive: last moment before April 1
        let nextMonthStart = cal.date(byAdding: .month, value: 1, to: expectedStart)!
        #expect(end < nextMonthStart)
        #expect(cal.isDate(end, inSameDayAs: cal.date(byAdding: .day, value: -1, to: nextMonthStart)!))
    }

    @Test("Months between produces month anchors inclusive")
    func monthsBetweenAnchors() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 3))!
        let end   = cal.date(from: DateComponents(year: 2025, month: 3, day: 20))!

        let months = cal.monthsBetween(start: start, end: end)
        #expect(months.count == 3)

        let expected = [
            cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!,
            cal.date(from: DateComponents(year: 2025, month: 2, day: 1))!,
            cal.date(from: DateComponents(year: 2025, month: 3, day: 1))!
        ]
        #expect(months == expected)
    }
}
#endif
