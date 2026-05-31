import SwiftUI
import SwiftData
import Foundation

@main
struct BrickDotApp: App {
    // Read user-selected appearance from SettingsView
    @AppStorage(AppPrefsKey.colorScheme)  private var appearanceRaw: String = "system"   // system | light | dark
    @AppStorage(AppPrefsKey.accentPreset) private var accentRaw: String = "indigo"      // blue | indigo | brick | green | orange

    var body: some Scene {
        WindowGroup {
            RootView() // your starting view
                .preferredColorScheme(colorScheme(from: appearanceRaw))
                .tint(accentColor(from: accentRaw))
        }
        .modelContainer(for: [
            Entry.self,
            Client.self,
            Invoice.self,
            Subtask.self,
            TimeLog.self,
            EntryTemplate.self,
            TemplateSubtask.self
        ], cloudKitDatabase: .automatic)
    }

    // MARK: - Appearance mapping
    private func colorScheme(from raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil    // system
        }
    }
    private func accentColor(from raw: String) -> Color {
        switch raw {
        case "blue":   return .blue
        case "indigo": return .indigo
        case "brick":  return Color(red: 0.79, green: 0.25, blue: 0.25)
        case "green":  return .green
        case "orange": return .orange
        default:       return .indigo
        }
    }
}
