import Foundation

extension Double {
    /// Formats a Double representing hours into a compact string like "1h 15m" or "45m".
    var hoursMinutesString: String {
        let mins = Int((self * 60).rounded())
        let hr = mins / 60
        let mn = mins % 60
        return hr > 0 ? "\(hr)h \(mn)m" : "\(mn)m"
    }
}
