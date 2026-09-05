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
            UserDefaults.standard.set(false, forKey: "cloudkit.fallbackToLocal")
            StoreMode.current = .cloudKit
            return container
        }

        // CloudKit init failed — fall back to local-only storage.
        // Do NOT delete the store; the data is still there and may sync
        // once the CloudKit issue resolves on next launch.
        //
        // A schema mistake (e.g. a relationship with no inverse) lands here
        // and silently disables sync app-wide, so the flag is only cleared
        // by an actual CloudKit success above — never blindly on launch.
        let localConfig = ModelConfiguration(cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
            UserDefaults.standard.set(true, forKey: "cloudkit.fallbackToLocal")
            StoreMode.current = .localOnly
            return container
        }

        // Last resort: if even local fails, use a fresh in-memory store so the
        // app at least launches. StoreStatusBanner then says so — silently
        // handing back an empty database looks identical to having no work,
        // and anything entered here is lost on quit.
        let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        StoreMode.current = .inMemory
        return try! ModelContainer(for: schema, configurations: [memoryConfig])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, currentTheme)
                .preferredColorScheme(colorScheme(from: appearanceRaw))
                .tint(currentTheme.accent)
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
                    }
                    #endif
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding is the natural moment: the data is settled and
            // serialising it can't jank the UI. Nothing called this before, so
            // backups only happened if you visited the Export screen and tapped
            // the button — which is not what "Last Auto-Backup" implied.
            if phase == .background {
                AutoBackup.performIfDue(ctx: container.mainContext)
            }

            if phase == .active {
                // Safety net: if backgrounding never got a clean run — force quit,
                // a crash — catch up once it is well overdue. Never on a normal
                // launch, so this can't slow the app opening.
                let neglected = AutoBackup.Schedule.lastRun
                    .map { Date().timeIntervalSince($0) >= AutoBackup.Schedule.interval * 2 }
                    ?? true
                if neglected { AutoBackup.performIfDue(ctx: container.mainContext) }

                refreshNotifications()
                #if targetEnvironment(macCatalyst)
                // Deliberately not stopped when the window loses focus — the
                // whole point is that it answers while BrickDot sits in the
                // background and the conversation happens elsewhere. It dies
                // with the process.
                CoachBridgeServer.shared.start(container: container)
                #endif
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
