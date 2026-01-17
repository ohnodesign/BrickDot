// Utilities/AutoBackup.swift
import Foundation
import SwiftData

extension Notification.Name {
    static let autoBackupDidFinish = Notification.Name("AutoBackupDidFinish")
}

enum AutoBackup {
    /// Performs backup asynchronously to avoid blocking the main thread.
    /// Call this from UI code - it dispatches to a background queue.
    static func perform(ctx: ModelContext) {
        // Capture the data on the current thread (ModelContext is not Sendable)
        let data: Data
        do {
            data = try Backup.makeJSONData(ctx: ctx)
        } catch {
            NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                "success": false,
                "message": error.localizedDescription.isEmpty ? "Backup failed." : error.localizedDescription
            ])
            return
        }

        // Dispatch file I/O (including potentially blocking iCloud operations) to a background queue
        DispatchQueue.global(qos: .utility).async {
            performBackupIO(data: data)
        }
    }

    /// Internal method that performs potentially blocking file I/O on a background thread.
    private static func performBackupIO(data: Data) {
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
                NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                    "success": true,
                    "message": "Backup completed. Saved to Documents and your chosen folder (if set)."
                ])
                UserDefaults.standard.set(Date(), forKey: "backup.lastRun")
            }
        } catch {
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

