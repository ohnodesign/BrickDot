// Utilities/Backup.swift
import Foundation
import SwiftData

/// JSON payload for backup. We key relationships by client.name (unique in your app),
/// so we don't rely on SwiftData's PersistentIdentifier / a custom UUID.
// ---- DTOs (near top of Backup.swift)
struct BackupPayload: Codable {
    var exportedAt: Date
    var appVersion: String
    var clients: [ClientDTO]
    var entries: [EntryDTO]
}

struct ClientDTO: Codable {
    var name: String
    var rate: Double
    var colorIndex: Int?
    var shortcode: String?
}

struct SubtaskDTO: Codable {
    var title: String
    var hours: Double
    var isDone: Bool
}

struct EntryDTO: Codable {
    var serviceDate: Date
    var service: String
    var detail: String
    var hours: Double
    var rate: Double
    var clientName: String
    var isInProgress: Bool
    var timerStartedAt: Date?
    var status: EntryStatus?
    var starred: Bool?
    var notes: String?
    var subtasks: [SubtaskDTO]?
    var dueDate: Date?
    var billOnCompletion: Bool?
}

enum BackupError: Error, LocalizedError {
    case badData
    case decodeFailed
    case encodeFailed
    case fileMissing
    case writeFailed
    case missingClientForEntry(String)

    var errorDescription: String? {
        switch self {
        case .badData: return "Data was not valid."
        case .decodeFailed: return "Could not decode backup file."
        case .encodeFailed: return "Could not encode data to JSON."
        case .fileMissing: return "Backup file not found."
        case .writeFailed: return "Could not write backup file."
        case .missingClientForEntry(let n): return "Client “\(n)” not found for one or more entries."
        }
    }
}

struct ImportReport {
    let importedClients: Int
    let importedEntries: Int
    let hadLegacyStarred: Bool
}

enum Backup {

    // MARK: - Public API

    /// Build the full JSON *data* in-memory (used by AutoBackup & manual export).
    static func makeJSONData(ctx: ModelContext) throws -> Data {
        let clients: [Client] = (try? ctx.fetch(FetchDescriptor<Client>())) ?? []
        let entries: [Entry]  = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []

        // Clients keyed by name; if duplicates exist, keep the first (names should be unique in UI).
        // We still export all as a flat list.
        let clientDTOs: [ClientDTO] = clients.map {
            ClientDTO(name: $0.name, rate: $0.rate, colorIndex: $0.colorIndex, shortcode: $0.shortcode.isEmpty ? nil : $0.shortcode)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // in makeJSONData(ctx:)
        let entryDTOs: [EntryDTO] = entries.map { entry in
            let subtaskDTOs: [SubtaskDTO]? = entry.subtasksList.isEmpty ? nil : entry.subtasksList.map {
                SubtaskDTO(title: $0.title, hours: $0.hours, isDone: $0.isDone)
            }
            return EntryDTO(
                serviceDate: entry.serviceDate,
                service: entry.service,
                detail: entry.detail,
                hours: entry.hours,
                rate: entry.rate,
                clientName: entry.clientName,
                isInProgress: (entry.status == .inProgress),
                timerStartedAt: entry.timerStartedAt,
                status: entry.status,
                starred: entry.isImportant,
                notes: entry.notes.isEmpty ? nil : entry.notes,
                subtasks: subtaskDTOs,
                dueDate: entry.dueDate,
                billOnCompletion: entry.billOnCompletion ? true : nil
            )
        }

        let payload = BackupPayload(
            exportedAt: Date(),
            appVersion: appVersionString(),
            clients: clientDTOs,
            entries: entryDTOs
        )

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(payload) else { throw BackupError.encodeFailed }
        return data
    }

    /// Manual export: writes a JSON into **Documents** and returns its URL.
    @discardableResult
    static func exportJSON(ctx: ModelContext, fileName: String? = nil) throws -> URL {
        let data = try makeJSONData(ctx: ctx)
        let name = (fileName?.nonEmpty ?? defaultBackupName()) + ".json"
        let url = documentsDirectory().appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            throw BackupError.writeFailed
        }
    }

    /// Manual import from a URL (upsert by client name; entries appended).
    static func importJSON(ctx: ModelContext, url: URL) throws {
        guard let data = try? Data(contentsOf: url) else { throw BackupError.fileMissing }
        try importJSON(ctx: ctx, data: data)
    }

    /// Manual import from a URL (returns a report with legacy flags info).
    static func importJSONWithReport(ctx: ModelContext, url: URL) throws -> ImportReport {
        guard let data = try? Data(contentsOf: url) else { throw BackupError.fileMissing }
        return try importJSONWithReport(ctx: ctx, data: data)
    }

    /// Restore from most recent auto-backup (if present).
    static func restoreLatestAutoBackup(ctx: ModelContext) throws {
        guard let url = latestAutoBackupURL() else { throw BackupError.fileMissing }
        try importJSON(ctx: ctx, url: url)
    }

    /// Import and return a report (non-throwing for legacy flags detection).
    static func importJSONWithReport(ctx: ModelContext, data: Data) throws -> ImportReport {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let payload = try? dec.decode(BackupPayload.self, from: data) else {
            throw BackupError.decodeFailed
        }

        // Fetch existing
        var existingClients: [Client] = (try? ctx.fetch(FetchDescriptor<Client>())) ?? []
        var clientIndex = Dictionary(uniqueKeysWithValues: existingClients.map { ($0.name.lowercased(), $0) })

        // Upsert clients
        var importedClients = 0
        for c in payload.clients {
            let key = c.name.lowercased()
            if let match = clientIndex[key] {
                match.name = c.name
                match.rate = c.rate
                if let ci = c.colorIndex { match.colorIndex = ci }
                if let sc = c.shortcode, !sc.isEmpty { match.shortcode = sc }
            } else {
                let model = Client(name: c.name, rate: c.rate, colorIndex: c.colorIndex ?? 0)
                model.shortcode = c.shortcode ?? ""
                ctx.insert(model)
                clientIndex[key] = model
                existingClients.append(model)
                importedClients += 1
            }
        }

        let existingEntries: [Entry] = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []
        let existingEntryKeys = Set(existingEntries.map { entryDeduplicationKey($0.clientName, $0.serviceDate, $0.service, $0.detail, $0.hours) })

        var importedEntries = 0
        var hadLegacyStarred = false

        for e in payload.entries {
            let key = e.clientName.lowercased()
            guard let client = clientIndex[key] else { throw BackupError.missingClientForEntry(e.clientName) }

            let dedupKey = entryDeduplicationKey(e.clientName, e.serviceDate, e.service, e.detail, e.hours)
            if existingEntryKeys.contains(dedupKey) { continue }

            let inferredStatus: EntryStatus = e.status ?? (e.isInProgress ? .inProgress : .todo)
            if e.starred == nil { hadLegacyStarred = true }

            let model = Entry(
                serviceDate: e.serviceDate,
                service: e.service,
                detail: e.detail,
                hours: e.hours,
                rate: e.rate,
                client: client,
                status: inferredStatus,
                timerStartedAt: e.timerStartedAt,
                isImportant: e.starred ?? false,
                notes: e.notes ?? "",
                dueDate: e.dueDate,
                billOnCompletion: e.billOnCompletion ?? false
            )
            ctx.insert(model)
            for st in e.subtasks ?? [] {
                let subtask = Subtask(title: st.title, parent: model, hours: st.hours, isDone: st.isDone)
                ctx.insert(subtask)
                model.subtasksList.append(subtask)
            }
            importedEntries += 1
        }

        try? ctx.save()
        return ImportReport(importedClients: importedClients, importedEntries: importedEntries, hadLegacyStarred: hadLegacyStarred)
    }

    /// Manual import from Data (upsert by client name; entries appended).
    static func importJSON(ctx: ModelContext, data: Data) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let payload = try? dec.decode(BackupPayload.self, from: data) else {
            throw BackupError.decodeFailed
        }

        // Fetch existing
        var existingClients: [Client] = (try? ctx.fetch(FetchDescriptor<Client>())) ?? []
        // Build index by name (case-insensitive)
        var clientIndex = Dictionary(uniqueKeysWithValues:
            existingClients.map { ($0.name.lowercased(), $0) }
        )

        // Upsert clients by name
        for c in payload.clients {
            let key = c.name.lowercased()
            if let match = clientIndex[key] {
                match.name = c.name       // keep canonical casing from backup
                match.rate = c.rate
                if let ci = c.colorIndex { match.colorIndex = ci }
                if let sc = c.shortcode, !sc.isEmpty { match.shortcode = sc }
            } else {
                let model = Client(name: c.name, rate: c.rate, colorIndex: c.colorIndex ?? 0)
                model.shortcode = c.shortcode ?? ""
                ctx.insert(model)
                clientIndex[key] = model
                existingClients.append(model)
            }
        }

        let existingEntries: [Entry] = (try? ctx.fetch(FetchDescriptor<Entry>())) ?? []
        let existingEntryKeys = Set(existingEntries.map { entryDeduplicationKey($0.clientName, $0.serviceDate, $0.service, $0.detail, $0.hours) })

        for e in payload.entries {
            let key = e.clientName.lowercased()
            guard let client = clientIndex[key] else {
                throw BackupError.missingClientForEntry(e.clientName)
            }

            let dedupKey = entryDeduplicationKey(e.clientName, e.serviceDate, e.service, e.detail, e.hours)
            if existingEntryKeys.contains(dedupKey) { continue }

            let inferredStatus: EntryStatus = e.status ?? (e.isInProgress ? .inProgress : .todo)

            let model = Entry(
                serviceDate: e.serviceDate,
                service: e.service,
                detail: e.detail,
                hours: e.hours,
                rate: e.rate,
                client: client,
                status: inferredStatus,
                timerStartedAt: e.timerStartedAt,
                isImportant: e.starred ?? false,
                notes: e.notes ?? "",
                dueDate: e.dueDate,
                billOnCompletion: e.billOnCompletion ?? false
            )
            ctx.insert(model)
            for st in e.subtasks ?? [] {
                let subtask = Subtask(title: st.title, parent: model, hours: st.hours, isDone: st.isDone)
                ctx.insert(subtask)
                model.subtasksList.append(subtask)
            }
        }

        try? ctx.save()
    }

    // MARK: - Files (Documents directory + auto-backup helpers)

    static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static func defaultBackupName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        return "Backup_\(df.string(from: Date()))"
    }

    static func latestAutoBackupURL() -> URL? {
        let fm = FileManager.default
        let dir = documentsDirectory()
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let autos = files.filter { $0.lastPathComponent.hasPrefix("Backup_") && $0.pathExtension.lowercased() == "json" }
        let sorted = autos.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        return sorted.first
    }

    // MARK: - App version

    private static func entryDeduplicationKey(_ clientName: String, _ serviceDate: Date, _ service: String, _ detail: String, _ hours: Double) -> String {
        let dateStr = ISO8601DateFormatter().string(from: serviceDate)
        return "\(clientName.lowercased())|\(dateStr)|\(service)|\(detail)|\(hours)"
    }

    private static func appVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
