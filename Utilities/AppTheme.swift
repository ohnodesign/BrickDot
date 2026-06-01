import SwiftUI

// MARK: - Theme Definition

struct AppTheme {
    // Backgrounds
    let background: Color
    let cardBackground: Color
    let sidebarBackground: Color
    let divider: Color

    // Text
    let primaryText: Color
    let secondaryText: Color
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

// MARK: - Apple Professional Theme

extension AppTheme {
    static let professional = AppTheme(
        background:        Color(hex: "F8F9FB"),
        cardBackground:    Color(hex: "FFFFFF"),
        sidebarBackground: Color(hex: "F3F4F6"),
        divider:           Color(hex: "E5E7EB"),

        primaryText:       Color(hex: "111827"),
        secondaryText:     Color(hex: "6B7280"),
        mutedText:         Color(hex: "9CA3AF"),

        accent:            Color(hex: "2563EB"),
        accentHover:       Color(hex: "1D4ED8"),
        accentLight:       Color(hex: "DBEAFE"),

        success:           Color(hex: "16A34A"),
        successLight:      Color(hex: "DCFCE7"),
        dueToday:          Color(hex: "EA580C"),
        dueTodayLight:     Color(hex: "FED7AA"),
        overdue:           Color(hex: "DC2626"),
        overdueLight:      Color(hex: "FEE2E2"),
        running:           Color(hex: "7C3AED"),
        runningLight:      Color(hex: "EDE9FE"),

        revenue:           Color(hex: "16A34A"),
        revenueLight:      Color(hex: "DCFCE7"),

        selectedClient:    Color(hex: "DBEAFE"),
        selectedBorder:    Color(hex: "2563EB"),

        quickCapture:      Color(hex: "2563EB"),
        buttonText:        Color(hex: "FFFFFF"),

        priorityTask:      Color(hex: "DC2626")
    )
}

// MARK: - Leica Minimal Theme

extension AppTheme {
    static let minimal = AppTheme(
        background:        Color(hex: "F7F6F3"),
        cardBackground:    Color(hex: "FFFFFF"),
        sidebarBackground: Color(hex: "EFEDE8"),
        divider:           Color(hex: "DDD8D0"),

        primaryText:       Color(hex: "111111"),
        secondaryText:     Color(hex: "666666"),
        mutedText:         Color(hex: "999999"),

        accent:            Color(hex: "B91C1C"),
        accentHover:       Color(hex: "991B1B"),
        accentLight:       Color(hex: "FEE2E2"),

        success:           Color(hex: "15803D"),
        successLight:      Color(hex: "DCFCE7"),
        dueToday:          Color(hex: "C2410C"),
        dueTodayLight:     Color(hex: "FFEDD5"),
        overdue:           Color(hex: "B91C1C"),
        overdueLight:      Color(hex: "FEE2E2"),
        running:           Color(hex: "444444"),
        runningLight:      Color(hex: "E5E5E5"),

        revenue:           Color(hex: "15803D"),
        revenueLight:      Color(hex: "DCFCE7"),

        selectedClient:    Color(hex: "FEE2E2"),
        selectedBorder:    Color(hex: "B91C1C"),

        quickCapture:      Color(hex: "B91C1C"),
        buttonText:        Color(hex: "FFFFFF"),

        priorityTask:      Color(hex: "B91C1C")
    )
}

// MARK: - Monochrome Theme

extension AppTheme {
    static let monochrome = AppTheme(
        background:        Color(hex: "F7F7F7"),
        cardBackground:    Color(hex: "FFFFFF"),
        sidebarBackground: Color(hex: "EFEFEF"),
        divider:           Color(hex: "D9D9D9"),

        primaryText:       Color(hex: "111111"),
        secondaryText:     Color(hex: "666666"),
        mutedText:         Color(hex: "999999"),

        accent:            Color(hex: "1A1A1A"),
        accentHover:       Color(hex: "000000"),
        accentLight:       Color(hex: "E5E5E5"),

        success:           Color(hex: "333333"),
        successLight:      Color(hex: "F0F0F0"),
        dueToday:          Color(hex: "555555"),
        dueTodayLight:     Color(hex: "EFEFEF"),
        overdue:           Color(hex: "111111"),
        overdueLight:      Color(hex: "E5E5E5"),
        running:           Color(hex: "777777"),
        runningLight:      Color(hex: "F0F0F0"),

        revenue:           Color(hex: "333333"),
        revenueLight:      Color(hex: "F0F0F0"),

        selectedClient:    Color(hex: "E5E5E5"),
        selectedBorder:    Color(hex: "111111"),

        quickCapture:      Color(hex: "111111"),
        buttonText:        Color(hex: "FFFFFF"),

        priorityTask:      Color(hex: "000000")
    )
}

// MARK: - Monochrome Dark Executive Theme

extension AppTheme {
    static let monochromeDark = AppTheme(
        background:        Color(hex: "F2F2F2"),
        cardBackground:    Color(hex: "FFFFFF"),
        sidebarBackground: Color(hex: "E8E8E8"),
        divider:           Color(hex: "CCCCCC"),

        primaryText:       Color(hex: "000000"),
        secondaryText:     Color(hex: "555555"),
        mutedText:         Color(hex: "888888"),

        accent:            Color(hex: "222222"),
        accentHover:       Color(hex: "111111"),
        accentLight:       Color(hex: "E8E8E8"),

        success:           Color(hex: "222222"),
        successLight:      Color(hex: "E8E8E8"),
        dueToday:          Color(hex: "444444"),
        dueTodayLight:     Color(hex: "EFEFEF"),
        overdue:           Color(hex: "000000"),
        overdueLight:      Color(hex: "E0E0E0"),
        running:           Color(hex: "666666"),
        runningLight:      Color(hex: "F0F0F0"),

        revenue:           Color(hex: "222222"),
        revenueLight:      Color(hex: "E8E8E8"),

        selectedClient:    Color(hex: "E0E0E0"),
        selectedBorder:    Color(hex: "000000"),

        quickCapture:      Color(hex: "222222"),
        buttonText:        Color(hex: "FFFFFF"),

        priorityTask:      Color(hex: "000000")
    )
}

// MARK: - Theme Key (for settings)

enum ThemeKey: String, CaseIterable {
    case professional = "professional"
    case minimal = "minimal"
    case monochrome = "monochrome"
    case monochromeDark = "monochromeDark"

    var displayName: String {
        switch self {
        case .professional: return "Apple Professional"
        case .minimal: return "Minimal"
        case .monochrome: return "Monochrome"
        case .monochromeDark: return "Monochrome Executive"
        }
    }

    var theme: AppTheme {
        switch self {
        case .professional: return .professional
        case .minimal: return .minimal
        case .monochrome: return .monochrome
        case .monochromeDark: return .monochromeDark
        }
    }
}

// MARK: - Environment Key

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .professional
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Color hex initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
