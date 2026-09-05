// Utilities/AutoBackup.swift
import Foundation
import SwiftData

extension Notification.Name {
    static let autoBackupDidFinish = Notification.Name("AutoBackupDidFinish")
}

enum AutoBackup {
    /// Performs backup asynchronously to avoid blocking the main thread.
    /// Call this from UI code - it dispatches to a background queue.
    /// Keys and interval for the scheduled backup.
    enum Schedule {
        static let enabledKey = "backup.automatic"
        static let lastRunKey = "backup.lastRun"
        static let interval: TimeInterval = 24 * 60 * 60

        /// Defaults to on — the Export screen has always said "Last Auto-Backup",
        /// so this is the behaviour the UI already promised.
        static var isEnabled: Bool {
            get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
            set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
        }

        static var lastRun: Date? {
            UserDefaults.standard.object(forKey: lastRunKey) as? Date
        }

        static var isDue: Bool {
            guard isEnabled else { return false }
            guard let last = lastRun else { return true }
            return Date().timeIntervalSince(last) >= interval
        }
    }

    /// Runs a backup only if one hasn't happened in the last day. Silent: a
    /// scheduled backup shouldn't announce itself the way the manual button does.
    ///
    /// CloudKit is sync, not backup — a bad merge or a delete propagates to every
    /// device in seconds. These JSON snapshots are the only thing that doesn't.
    static func performIfDue(ctx: ModelContext) {
        guard Schedule.isDue else { return }
        perform(ctx: ctx, announce: false)
    }

    static func perform(ctx: ModelContext, announce: Bool = true) {
        // Capture the data on the current thread (ModelContext is not Sendable)
        let data: Data
        do {
            data = try Backup.makeJSONData(ctx: ctx)
        } catch {
            if announce {
                NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                    "success": false,
                    "message": error.localizedDescription.isEmpty ? "Backup failed." : error.localizedDescription
                ])
            }
            return
        }

        // Dispatch file I/O (including potentially blocking iCloud operations) to a background queue
        DispatchQueue.global(qos: .utility).async {
            performBackupIO(data: data, announce: announce)
        }
    }

    /// Internal method that performs potentially blocking file I/O on a background thread.
    private static func performBackupIO(data: Data, announce: Bool) {
        do {
            let name = Backup.defaultBackupName() + ".json"
            let url = Backup.documentsDirectory().appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try pruneOldBackups(keeping: 14)

            // Also write to user-chosen folder (if set)
            if let bookmark = UserDefaults.standard.data(forKey: "backup.folder.bookmark") {
                var isStale = false
                if let folderURL = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    // Refresh stale bookmark if needed
                    if isStale, let refreshed = try? folderURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        UserDefaults.standard.set(refreshed, forKey: "backup.folder.bookmark")
                    }

                    // Begin security scope
                    let ok = folderURL.startAccessingSecurityScopedResource()
                    defer { if ok { folderURL.stopAccessingSecurityScopedResource() } }

                    // Nudge hydration if iCloud folder
                    if (try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: folderURL)
                    }

                    let name = Backup.defaultBackupName() + ".json"
                    let dest = folderURL.appendingPathComponent(name)

                    // Coordinate the write
                    let coordinator = NSFileCoordinator()
                    var coordError: NSError?
                    var writeError: Error?
                    coordinator.coordinate(writingItemAt: dest, options: [], error: &coordError) { url in
                        do {
                            try data.write(to: url, options: .atomic)
                        } catch {
                            writeError = error
                        }
                    }
                    // Swallow errors for now (optional: log them)
                    _ = coordError
                    _ = writeError
                }
            }

            // Post notification on main thread
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date(), forKey: Schedule.lastRunKey)
                guard announce else { return }
                NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                    "success": true,
                    "message": "Backup completed. Saved to Documents and your chosen folder (if set)."
                ])
            }
        } catch {
            guard announce else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                    "success": false,
                    "message": error.localizedDescription.isEmpty ? "Backup failed." : error.localizedDescription
                ])
            }
        }
    }

    private static func pruneOldBackups(keeping: Int) throws {
        let fm = FileManager.default
        let dir = Backup.documentsDirectory()
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent.hasPrefix("Backup_") && $0.pathExtension.lowercased() == "json" }

        let sorted = try files.sorted {
            let a = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let b = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return a > b
        }

        if sorted.count > keeping {
            for url in sorted.dropFirst(keeping) {
                try? fm.removeItem(at: url)
            }
        }
    }
}

