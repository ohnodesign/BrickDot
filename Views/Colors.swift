// Views/Colors.swift
import SwiftUI

// MARK: - Custom App Colors
extension Color {
    /// BrickDot accent red used across buttons, status indicators, etc.
    static let brick = Color(red: 0.79, green: 0.25, blue: 0.25)
}

// MARK: - Entry Status → Color Mapping
extension EntryStatus {
    /// Returns a standardized color for each status.
    var color: Color {
        switch self {
        case .todo:
            return .orange
        case .inProgress:
            return .brick
        case .done:
            return .green
        @unknown default:
            return .gray
        }
    }
}
