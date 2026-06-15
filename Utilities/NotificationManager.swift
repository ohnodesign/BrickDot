import Foundation
import UserNotifications
import SwiftData

struct NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    // MARK: - Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    self.defaults.set(true, forKey: AppPrefsKey.notificationsEnabled)
                }
            }
        }
    }

    // MARK: - Reschedule All

    func reschedule(entries: [Entry]) {
        center.removeAllPendingNotificationRequests()

        guard defaults.bool(forKey: AppPrefsKey.notificationsEnabled) else { return }

        let open = entries.filter { $0.status != .done }

        if defaults.object(forKey: AppPrefsKey.notifyDueToday) == nil || defaults.bool(forKey: AppPrefsKey.notifyDueToday) {
            scheduleDueTodayNotifications(open)
        }
        if defaults.object(forKey: AppPrefsKey.notifyOverdue) == nil || defaults.bool(forKey: AppPrefsKey.notifyOverdue) {
            scheduleOverdueNotification(open)
        }
        if defaults.object(forKey: AppPrefsKey.notifyCOMMReply) == nil || defaults.bool(forKey: AppPrefsKey.notifyCOMMReply) {
            scheduleCOMMReminders(open)
        }
        if defaults.object(forKey: AppPrefsKey.notifyNoTimeLogged) == nil || defaults.bool(forKey: AppPrefsKey.notifyNoTimeLogged) {
            scheduleNoTimeLoggedReminder(entries: entries)
        }

        updateBadge(open)
    }

    // MARK: - Badge (overdue count)

    private func updateBadge(_ openEntries: [Entry]) {
        let now = Date()
        let overdueCount = openEntries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: now)
        }.count
        center.setBadgeCount(overdueCount)
    }

    // MARK: - Due Today

    private func scheduleDueTodayNotifications(_ entries: [Entry]) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) else { return }

        let dueToday = entries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= todayStart && due < todayEnd
        }

        guard !dueToday.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Due Today"
        if dueToday.count == 1, let e = dueToday.first {
            content.body = "\(e.service): \(e.detail.isEmpty ? e.clientName : e.detail)"
        } else {
            content.body = "You have \(dueToday.count) items due today."
        }
        content.sound = .default

        var morning = DateComponents()
        morning.hour = 8
        morning.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: morning, repeats: false)
        let request = UNNotificationRequest(identifier: "due-today", content: content, trigger: trigger)
        center.add(request)

        // Also schedule for tomorrow morning: items due tomorrow
        scheduleDueTomorrowNotification(entries)
    }

    private func scheduleDueTomorrowNotification(_ entries: [Entry]) {
        let cal = Calendar.current
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())),
              let tomorrowEnd = cal.date(byAdding: .day, value: 1, to: tomorrowStart) else { return }

        let dueTomorrow = entries.filter { e in
            guard let due = e.dueDate else { return false }
            return due >= tomorrowStart && due < tomorrowEnd
        }

        guard !dueTomorrow.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Due Tomorrow"
        if dueTomorrow.count == 1, let e = dueTomorrow.first {
            content.body = "\(e.service): \(e.detail.isEmpty ? e.clientName : e.detail)"
        } else {
            content.body = "You have \(dueTomorrow.count) items due tomorrow."
        }
        content.sound = .default

        var tomorrowMorning = cal.dateComponents([.year, .month, .day], from: tomorrowStart)
        tomorrowMorning.hour = 8
        tomorrowMorning.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: tomorrowMorning, repeats: false)
        let request = UNNotificationRequest(identifier: "due-tomorrow", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Overdue

    private func scheduleOverdueNotification(_ entries: [Entry]) {
        let now = Date()
        let overdue = entries.filter { e in
            guard let due = e.dueDate else { return false }
            return due < Calendar.current.startOfDay(for: now)
        }

        guard !overdue.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Overdue Items"
        if overdue.count == 1, let e = overdue.first {
            content.body = "\(e.service) for \(e.clientName): \(e.detail.isEmpty ? "past due" : e.detail)"
        } else {
            content.body = "You have \(overdue.count) overdue items that need attention."
        }
        content.sound = .default

        var morning = DateComponents()
        morning.hour = 9
        morning.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: morning, repeats: false)
        let request = UNNotificationRequest(identifier: "overdue", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - COMM Needs Reply

    private func scheduleCOMMReminders(_ entries: [Entry]) {
        let commEntries = entries.filter { e in
            e.service == "COMM"
            && e.commDirection == "needsReply"
            && e.status != .done
        }

        for (i, entry) in commEntries.prefix(10).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Needs Reply"
            let contact = entry.commContact ?? entry.clientName
            let channel = entry.commChannel ?? "message"
            content.body = "\(contact) — \(channel): \(entry.detail.isEmpty ? "Awaiting your reply" : entry.detail)"
            content.sound = .default

            let reminderDate: Date
            let fourHoursAfter = entry.createdAt.addingTimeInterval(4 * 3600)
            if fourHoursAfter > Date() {
                reminderDate = fourHoursAfter
            } else {
                // Next day at 9am if the 4-hour window already passed
                let cal = Calendar.current
                guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = 9
                comps.minute = 0
                reminderDate = cal.date(from: comps) ?? Date().addingTimeInterval(3600)
            }

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "comm-reply-\(i)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    // MARK: - No Time Logged Today

    private func scheduleNoTimeLoggedReminder(entries: [Entry]) {
        let hasLoggedToday = entries.contains { e in
            e.timeLogsList.contains { Calendar.current.isDateInToday($0.addedAt) }
        }

        guard !hasLoggedToday else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time Tracking"
        content.body = "You haven't logged any time today."
        content.sound = .default

        var evening = DateComponents()
        evening.hour = 18
        evening.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: evening, repeats: false)
        let request = UNNotificationRequest(identifier: "no-time-logged", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Cancel No-Time-Logged (call when time IS logged)

    func cancelNoTimeLoggedReminder() {
        center.removePendingNotificationRequests(withIdentifiers: ["no-time-logged"])
    }
}
