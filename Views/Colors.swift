// Views/Colors.swift
import SwiftUI

// MARK: - Custom App Colors
extension Color {
    /// BrickDot accent red used across buttons, status indicators, etc.
    static let brick = Color(red: 0.79, green: 0.25, blue: 0.25)
}

// MARK: - Client Color Palette

struct ClientColors {
    static let palette: [(name: String, color: Color)] = [
        ("Slate",    Color(red: 0.47, green: 0.53, blue: 0.60)),
        ("Blue",     Color(red: 0.20, green: 0.49, blue: 0.85)),
        ("Indigo",   Color(red: 0.35, green: 0.34, blue: 0.84)),
        ("Purple",   Color(red: 0.58, green: 0.33, blue: 0.78)),
        ("Pink",     Color(red: 0.85, green: 0.30, blue: 0.52)),
        ("Red",      Color(red: 0.82, green: 0.25, blue: 0.25)),
        ("Orange",   Color(red: 0.90, green: 0.49, blue: 0.13)),
        ("Amber",    Color(red: 0.85, green: 0.65, blue: 0.13)),
        ("Green",    Color(red: 0.22, green: 0.65, blue: 0.36)),
        ("Teal",     Color(red: 0.15, green: 0.60, blue: 0.62)),
    ]

    static func color(for index: Int) -> Color {
        guard index >= 0 && index < palette.count else { return palette[0].color }
        return palette[index].color
    }

    /// Auto-assign next color based on existing client count
    static func nextIndex(existingCount: Int) -> Int {
        existingCount % palette.count
    }
}

extension Client {
    var accentColor: Color {
        ClientColors.color(for: colorIndex)
    }
}

// MARK: - Client Color Picker View

struct ClientColorPicker: View {
    @Binding var selectedIndex: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(ClientColors.palette.enumerated()), id: \.offset) { index, item in
                Circle()
                    .fill(item.color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: selectedIndex == index ? 3 : 0)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .opacity(selectedIndex == index ? 1 : 0)
                    )
                    .onTapGesture { selectedIndex = index }
                    .accessibilityLabel(item.name)
            }
        }
        .padding(.vertical, 4)
    }
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
