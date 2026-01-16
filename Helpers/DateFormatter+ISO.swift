// Helpers/DateFormatter+ISO.swift
import Foundation

extension DateFormatter {
    static let iso8601Day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)  // explicit calendar fixes the error
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
