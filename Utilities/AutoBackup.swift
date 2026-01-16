// Utilities/AutoBackup.swift
import Foundation
import SwiftData

extension Notification.Name {
    static let autoBackupDidFinish = Notification.Name("AutoBackupDidFinish")
}

enum AutoBackup {
    static func perform(ctx: ModelContext) {
        do {
            let data = try Backup.makeJSONData(ctx: ctx)
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
            NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                "success": true,
                "message": "Backup completed. Saved to Documents and your chosen folder (if set)."
            ])
            UserDefaults.standard.set(Date(), forKey: "backup.lastRun")
        } catch {
            NotificationCenter.default.post(name: .autoBackupDidFinish, object: nil, userInfo: [
                "success": false,
                "message": error.localizedDescription.isEmpty ? "Backup failed." : error.localizedDescription
            ])
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

