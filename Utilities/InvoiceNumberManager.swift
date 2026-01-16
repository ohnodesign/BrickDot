import Foundation

/// Stores and generates sequential invoice numbers (e.g., "2025-1001", "2025-1002", …).
/// Persists to UserDefaults so the sequence survives app restarts.
enum InvoiceNumberManager {
    private static let key = "InvoiceNumberSequence.Current"

    /// Seed the sequence once. If already seeded, this does nothing.
    static func setInitialIfNeeded(_ firstNumber: String) {
        let ud = UserDefaults.standard
        if ud.string(forKey: key) == nil {
            ud.set(firstNumber, forKey: key)
        }
    }

    /// Peek current invoice number without advancing.
    static func current() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    /// Get the next invoice number and advance the stored value.
    @discardableResult
    static func nextAndAdvance() -> String {
        let ud = UserDefaults.standard
        let current = ud.string(forKey: key) ?? "1"
        let next = incrementPattern(current)
        ud.set(next, forKey: key)
        return current // return the one to use now; we've advanced to the following
    }

    /// If you ever need to force-set a particular number.
    static func overwrite(_ number: String) {
        UserDefaults.standard.set(number, forKey: key)
    }

    /// Increments the trailing numeric component while preserving the prefix.
    /// Examples:
    /// - "2025-1001" -> "2025-1002"
    /// - "INV-0009"  -> "INV-0010"
    /// - "1001"      -> "1002"
    private static func incrementPattern(_ s: String) -> String {
        // Find trailing digits
        let digits = s.reversed().prefix { $0.isNumber }.reversed()
        if digits.isEmpty {
            // No trailing digits; just append 1
            return s + "1"
        }
        let prefix = String(s.dropLast(digits.count))
        let numStr = String(digits)
        let width = numStr.count
        let n = (Int(numStr) ?? 0) + 1
        let padded = String(format: "%0\(width)d", n)
        return prefix + padded
    }
}
