import SwiftUI

// MARK: - Theme Key

enum ThemeKey: String, CaseIterable {
    case professional = "professional"   // BRICKDOT - APPLE PROFESSIONAL
    case minimal      = "minimal"        // BRICKDOT - LEICA INSPIRED

    var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .minimal:      return "Minimal"
        }
    }

    var theme: AppTheme {
        switch self {
        case .professional:
            return AppTheme(
                // Backgrounds
                background: Color(hex: "#F8F9FB"),
                cardBackground: Color(hex: "#FFFFFF"),
                sidebarBackground: Color(hex: "#F3F4F6"),
                divider: Color(hex: "#E5E7EB"),
                // Text
                textPrimary: Color(hex: "#111827"),
                textSecondary: Color(hex: "#6B7280"),
                mutedText: Color(hex: "#9CA3AF"),
                // Brand
                accent: Color(hex: "#2563EB"),
                accentHover: Color(hex: "#1D4ED8"),
                accentLight: Color(hex: "#DBEAFE"),
                // Status
                success: Color(hex: "#16A34A"),
                successLight: Color(hex: "#DCFCE7"),
                dueToday: Color(hex: "#EA580C"),
                dueTodayLight: Color(hex: "#FED7AA"),
                overdue: Color(hex: "#DC2626"),
                overdueLight: Color(hex: "#FEE2E2"),
                running: Color(hex: "#7C3AED"),
                runningLight: Color(hex: "#EDE9FE"),
                // Revenue
                revenue: Color(hex: "#16A34A"),
                revenueLight: Color(hex: "#DCFCE7"),
                // Clients
                selectedClient: Color(hex: "#DBEAFE"),
                selectedBorder: Color(hex: "#2563EB"),
                // Buttons
                quickCapture: Color(hex: "#2563EB"),
                buttonText: Color(hex: "#FFFFFF"),
                // Priority
                priorityTask: Color(hex: "#DC2626")
            )
        case .minimal:
            return AppTheme(
                // Backgrounds
                background: Color(hex: "#F7F6F3"),
                cardBackground: Color(hex: "#FFFFFF"),
                sidebarBackground: Color(hex: "#EFEDE8"),
                divider: Color(hex: "#DDD8D0"),
                // Text
                textPrimary: Color(hex: "#111111"),
                textSecondary: Color(hex: "#666666"),
                mutedText: Color(hex: "#999999"),
                // Brand
                accent: Color(hex: "#B91C1C"),
                accentHover: Color(hex: "#991B1B"),
                accentLight: Color(hex: "#FEE2E2"),
                // Status
                success: Color(hex: "#15803D"),
                successLight: Color(hex: "#DCFCE7"),
                dueToday: Color(hex: "#C2410C"),
                dueTodayLight: Color(hex: "#FFEDD5"),
                overdue: Color(hex: "#B91C1C"),
                overdueLight: Color(hex: "#FEE2E2"),
                running: Color(hex: "#444444"),
                runningLight: Color(hex: "#E5E5E5"),
                // Revenue
                revenue: Color(hex: "#15803D"),
                revenueLight: Color(hex: "#DCFCE7"),
                // Clients
                selectedClient: Color(hex: "#FEE2E2"),
                selectedBorder: Color(hex: "#B91C1C"),
                // Buttons
                quickCapture: Color(hex: "#B91C1C"),
                buttonText: Color(hex: "#FFFFFF"),
                // Priority
                priorityTask: Color(hex: "#B91C1C")
            )
        }
    }
}

// MARK: - App Theme

struct AppTheme {
    // Backgrounds
    let background: Color
    let cardBackground: Color
    let sidebarBackground: Color
    let divider: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let mutedText: Color

    // Brand
    let accent: Color
    let accentHover: Color
    let accentLight: Color

    // Status
    let success: Color
    let successLight: Color
    let dueToday: Color
    let dueTodayLight: Color
    let overdue: Color
    let overdueLight: Color
    let running: Color
    let runningLight: Color

    // Revenue
    let revenue: Color
    let revenueLight: Color

    // Clients
    let selectedClient: Color
    let selectedBorder: Color

    // Buttons
    let quickCapture: Color
    let buttonText: Color

    // Priority
    let priorityTask: Color
}

// MARK: - Environment Key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = ThemeKey.professional.theme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Small Color(hex:) helper

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
