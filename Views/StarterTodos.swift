import Foundation
import SwiftData
import SwiftUI

// MARK: - Setup actions

/// Destinations that first-run starter todos deep-link to.
enum SetupAction: String, CaseIterable {
    case profile
    case services
    case clients
    case reminders
    case importData

    /// Posts the navigation notification; RootView routes to the section.
    func navigate() {
        NotificationCenter.default.post(
            name: .navigateToSection,
            object: nil,
            userInfo: ["action": rawValue]
        )
        if self == .services {
            // SettingsView may not exist yet when the notification fires;
            // give it a beat to appear before asking it to expand Services.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .revealServicesEditor, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let navigateToSection = Notification.Name("navigateToSection")
    static let revealServicesEditor = Notification.Name("revealServicesEditor")
}

// MARK: - Seeding & auto-completion

enum StarterTodos {
    private static let seededKey = "onboarding.starterTodos.seeded"

    /// Seeds the first-run setup todos exactly once, and only into a store
    /// that is truly empty (an existing user's CloudKit data skips seeding).
    static func seedIfNeeded(_ ctx: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let entryCount = (try? ctx.fetchCount(FetchDescriptor<Entry>(predicate: Entry.workOnlyPredicate))) ?? 0
        let clientCount = (try? ctx.fetchCount(FetchDescriptor<Client>())) ?? 0
        guard entryCount == 0 && clientCount == 0 else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        let todos: [(title: String, notes: String, action: SetupAction)] = [
            ("Complete your profile",
             "Your name, company and logo appear on every invoice you send. Tap this task to open Profile.",
             .profile),
            ("Review your services",
             "Services are the categories you bill under (DESIGN, PHOTO, SALES…). Rename them or add your own. Tap this task to open Settings.",
             .services),
            ("Add your clients",
             "Each client stores an hourly rate and a quick-add shortcode. Tap this task to open Clients.",
             .clients),
            ("Turn on reminders",
             "Get nudged about due dates and timers you left running. Tap this task to open Settings.",
             .reminders),
            ("Import past work",
             "Already tracking time elsewhere? Bring in entries from a CSV file. Tap this task to open Export & Import.",
             .importData)
        ]

        let now = Date()
        for (index, todo) in todos.enumerated() {
            // Stagger serviceDates so the backlog lists them in this order.
            let entry = Entry(
                serviceDate: now.addingTimeInterval(TimeInterval(-index)),
                service: "SETUP",
                detail: todo.title,
                notes: todo.notes
            )
            entry.setupAction = todo.action.rawValue
            ctx.insert(entry)
        }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Marks setup todos done once the thing they ask for actually exists.
    /// (Import has no reliable signal — the user checks that one off.)
    static func autoComplete(_ ctx: ModelContext) {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.setupAction != nil })
        guard let setups = try? ctx.fetch(descriptor), !setups.isEmpty else { return }

        let openSetups = setups.filter { $0.status != .done }
        guard !openSetups.isEmpty else { return }

        let clientCount = (try? ctx.fetchCount(FetchDescriptor<Client>())) ?? 0
        let profile = ((try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []).first
        let profileDone = profile.map { !$0.displayName.isEmpty || !$0.companyName.isEmpty } ?? false
        let remindersOn = UserDefaults.standard.bool(forKey: AppPrefsKey.notificationsEnabled)

        var changed = false
        for entry in openSetups {
            let done: Bool
            switch SetupAction(rawValue: entry.setupAction ?? "") {
            case .profile:   done = profileDone
            case .services:  done = Constants.servicesCustomized
            case .clients:   done = clientCount > 0
            case .reminders: done = remindersOn
            default:         done = false
            }
            if done {
                entry.status = .done
                entry.completedAt = Date()
                changed = true
            }
        }
        if changed { try? ctx.save() }
    }
}
