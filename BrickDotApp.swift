import SwiftUI
import SwiftData
#if targetEnvironment(macCatalyst)
import UIKit
#endif

@main
struct BrickDotApp: App {
    @AppStorage(AppPrefsKey.colorScheme)  private var appearanceRaw: String = "system"
    @AppStorage("appearance.theme") private var themeRaw: String = "professional"
    @Environment(\.scenePhase) private var scenePhase

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
            UserProfile.self,
            SavedSearch.self
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
                    }
                    #if targetEnvironment(macCatalyst)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
                    }
                    #endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshNotifications()
            }
        }
    }

    private func refreshNotifications() {
        guard UserDefaults.standard.bool(forKey: AppPrefsKey.notificationsEnabled) else { return }
        let ctx = container.mainContext
        let entries = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []
        NotificationManager.shared.reschedule(entries: entries)
    }

    // MARK: - Appearance mapping
    private func colorScheme(from raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}
