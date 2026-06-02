import SwiftUI

public enum EntryStatus: String, Codable, CaseIterable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"
}

/// Canonical color mapping for status display across the app.
private func colorForStatus(_ status: EntryStatus) -> Color {
    switch status {
    case .todo:       return .orange
    case .inProgress: return .red
    case .done:       return .green
    }
}

/// Backward-compatible helpers for code that expects a free function.
@inline(__always)
func statusColor(_ status: EntryStatus) -> Color { colorForStatus(status) }

@inline(__always)
func statusColor(for status: EntryStatus) -> Color { colorForStatus(status) }

