import SwiftUI
import SwiftData
import Foundation

@main
struct BrickDotApp: App {
    @AppStorage(AppPrefsKey.colorScheme)  private var appearanceRaw: String = "system"
    @AppStorage(AppPrefsKey.accentPreset) private var accentRaw: String = "indigo"
    @AppStorage("appearance.theme") private var themeRaw: String = "professional"

    private var currentTheme: AppTheme {
        (ThemeKey(rawValue: themeRaw) ?? .professional).theme
    }

    let container: ModelContainer = {
        let schema = Schema([
            Entry.self,
            Client.self,
            Invoice.self,
            Subtask.self,
            TimeLog.self,
            EntryTemplate.self,
            TemplateSubtask.self,
            UserProfile.self
        ])

        let cloudConfig = ModelConfiguration(
            cloudKitDatabase: .automatic
        )

        // Try CloudKit-enabled store first
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // CloudKit init failed — fall back to local-only storage.
        // Do NOT delete the store; the data is still there and may sync
        // once the CloudKit issue resolves on next launch.
        let localConfig = ModelConfiguration(cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
            UserDefaults.standard.set(true, forKey: "cloudkit.fallbackToLocal")
            return container
        }

        // Last resort: if even local fails, use a fresh in-memory store
        // so the app at least launches (user can export/import later)
        let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [memoryConfig])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, currentTheme)
                .preferredColorScheme(colorScheme(from: appearanceRaw))
                .tint(currentTheme.accent)
                .onAppear {
                    if UserDefaults.standard.bool(forKey: "cloudkit.fallbackToLocal") {
                        UserDefaults.standard.set(false, forKey: "cloudkit.fallbackToLocal")
                        // Next launch will retry CloudKit
                    }
                }
        }
        .modelContainer(container)
    }

    // MARK: - Appearance mapping
    private func colorScheme(from raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
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
