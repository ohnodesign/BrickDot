import Foundation
import SwiftData

enum TaskDataSerializer {

    static func buildPayload(context: ModelContext) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let today = Calendar.current.startOfDay(for: Date())

        let allEntries = Entry.workOnly((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
        let allClients = (try? context.fetch(FetchDescriptor<Client>())) ?? []

        // Read-only. Task ids come from Entry.coachID, a value computed from the
        // SwiftData persistent id — there is no stored id field to assign, so
        // serialization never writes to the store.

        let openEntries = allEntries.filter { $0.status != .done }

        // Active timer (first running entry found)
        let running = openEntries.first { $0.timerStartedAt != nil }

        // Client summaries: unbilled hours for open entries
        var clientMinutes: [String: Double] = [:]
        for e in openEntries where e.invoice == nil {
            let name = e.clientName
            clientMinutes[name, default: 0] += e.hours * 60
        }

        // Build JSON
        var root: [String: Any] = [:]
        root["snapshot_date"] = iso8601Date(today)

        if let r = running, let started = r.timerStartedAt {
            let elapsed = Int(Date().timeIntervalSince(started) / 60)
            root["active_timer"] = [
                "task_id": r.coachID ?? "",
                "client": r.clientName,
                "description": r.detail.isEmpty ? r.service : r.detail,
                "started_at": iso.string(from: started),
                "elapsed_minutes": elapsed
            ] as [String: Any]
        }

        root["clients"] = allClients.map { c -> [String: Any] in
            [
                "name": c.name,
                "total_unlogged_minutes": Int(clientMinutes[c.name] ?? 0)
            ]
        }

        root["tasks"] = openEntries.map { e -> [String: Any] in
            var task: [String: Any] = [
                "id": e.coachID ?? "",
                "client": e.clientName,
                "description": e.detail.isEmpty ? e.service : e.detail,
                "category": e.service.lowercased(),
                "status": e.status == .inProgress ? "in_progress" : e.statusRaw.lowercased().replacingOccurrences(of: " ", with: "_"),
                "priority": e.isImportant ? "high" : "normal",
                "created_date": iso8601Date(e.createdAt),
                "last_activity_date": iso8601Date(e.serviceDate),
                "time_logged_minutes": Int(e.hours * 60)
            ]
            if !e.notes.isEmpty { task["notes"] = e.notes }
            if let due = e.dueDate { task["due_date"] = iso8601Date(due) }
            if e.service == "COMM" {
                if let ch = e.commChannel { task["comm_channel"] = ch }
                if let dir = e.commDirection { task["comm_direction"] = dir }
                if let con = e.commContact, !con.isEmpty { task["comm_contact"] = con }
            }

            let subtasks = e.subtasksList
            if !subtasks.isEmpty {
                task["subtasks"] = subtasks.map { s -> [String: Any] in
                    ["title": s.title, "done": s.isDone]
                }
            }

            return task
        }

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func iso8601Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
