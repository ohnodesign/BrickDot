import SwiftUI
import SwiftData
import Foundation

@main
struct BrickDotApp: App {
    @AppStorage(AppPrefsKey.colorScheme)  private var appearanceRaw: String = "system"
    @AppStorage(AppPrefsKey.accentPreset) private var accentRaw: String = "indigo"

    let container: ModelContainer = {
        let schema = Schema([
            Entry.self,
            Client.self,
            Invoice.self,
            Subtask.self,
            TimeLog.self,
            EntryTemplate.self,
            TemplateSubtask.self
        ])

        let cloudConfig = ModelConfiguration(
            cloudKitDatabase: .automatic
        )

        // Try CloudKit-enabled store first
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // If that fails (schema migration issue), delete the old store and retry
        let storeURL = ModelConfiguration().url
        let storePath = storeURL.path()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: storePath + suffix)
        }

        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // Last resort: local-only (no CloudKit)
        let localConfig = ModelConfiguration(cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: [localConfig])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme(from: appearanceRaw))
                .tint(accentColor(from: accentRaw))
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
