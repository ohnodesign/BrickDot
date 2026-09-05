import Foundation
import SwiftData

/// Read-only Coach tools.
///
/// These exist so the Coach can *ask* instead of being handed one big dump of
/// open work. That matters twice over: the system prompt stops growing with the
/// task list, and completed or invoiced work — deliberately absent from the
/// snapshot — becomes answerable.
///
/// Children (subtasks, time logs) are fetched from the store rather than read
/// off `entry.subtasksList` / `entry.timeLogsList`. Those relationship arrays are
/// cached on the Entry and can still hold a child whose row is already gone,
/// deleted on another device and merged in by CloudKit; such a model is
/// invalidated and reading a property off it traps. A fetch only ever returns
/// rows that exist. (Same reasoning as the `@Query` children in EditEntryView.)
enum CoachToolReader {

    static func execute(_ call: CoachToolCall, context: ModelContext) -> String {
        switch call.name {
        case "findTasks":       return findTasks(call, context)
        case "getTaskDetail":   return getTaskDetail(call, context)
        case "getClientSummary":return getClientSummary(call, context)
        case "listClients":     return listClients(call, context)
        default:                return json(["error": "Unknown read tool \(call.name)."])
        }
    }

    // MARK: - findTasks

    private static func findTasks(_ call: CoachToolCall, _ context: ModelContext) -> String {
        let all = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        let subtasksByParent = childSubtasks(context)
        let names = clientNames(context)

        // Status filter — open work only unless asked otherwise.
        let statusRaw = (call.string("status") ?? "open").lowercased()
        var candidates: [Entry]
        switch statusRaw {
        case "any":  candidates = all
        case "done": candidates = all.filter { $0.status == .done }
        case "open": candidates = all.filter { $0.status != .done }
        default:
            if let s = CoachToolFormat.statusFrom(statusRaw) {
                candidates = all.filter { $0.status == s }
            } else {
                candidates = all.filter { $0.status != .done }
            }
        }

        if let client = call.string("client")?.lowercased(), !client.isEmpty {
            candidates = candidates.filter { clientName($0, names).lowercased().contains(client) }
        }
        if let since = call.string("since").flatMap(CoachToolFormat.parseDate) {
            candidates = candidates.filter { $0.serviceDate >= since }
        }
        if let until = call.string("until").flatMap(CoachToolFormat.parseDate) {
            let end = Calendar.current.date(byAdding: .day, value: 1, to: until) ?? until
            candidates = candidates.filter { $0.serviceDate < end }
        }

        // Score against the query, if there is one.
        let query = (call.string("query") ?? "").lowercased()
        var ranked: [Entry]
        if query.isEmpty {
            ranked = candidates.sorted { $0.serviceDate > $1.serviceDate }
        } else {
            let terms = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let scored = candidates.compactMap { e -> (Entry, Int)? in
                let value = matchScore(e, query: query, terms: terms, client: clientName(e, names))
                return value > 0 ? (e, value) : nil
            }
            ranked = scored
                .sorted { $0.1 == $1.1 ? $0.0.serviceDate > $1.0.serviceDate : $0.1 > $1.1 }
                .map(\.0)
        }

        let limit = max(1, min(50, call.int("limit") ?? 15))
        let hits = Array(ranked.prefix(limit))

        let rows: [[String: Any]] = hits.map { e in
            var row: [String: Any] = [
                "id": e.coachID ?? "",
                "client": clientName(e, names),
                "description": CoachToolFormat.name(e),
                "service": e.service,
                "status": statusKey(e.status),
                "service_date": dayString(e.serviceDate),
                "hours_logged": round2(e.hours),
                "starred": e.isImportant
            ]
            if let due = e.dueDate { row["due_date"] = dayString(due) }
            if e.invoice != nil { row["invoiced"] = true }
            // Surfaced so the model can see (and report) whether something is
            // still an unreviewed capture rather than a considered task.
            if e.isQuickAdd { row["quick_capture"] = true }
            if !e.notes.isEmpty { row["notes"] = String(e.notes.prefix(300)) }
            let subs = subtasksByParent[e.persistentModelID] ?? []
            if !subs.isEmpty {
                row["subtasks"] = subs.map { ["title": $0.title, "done": $0.isDone] as [String: Any] }
            }
            return row
        }

        return json([
            "match_count": rows.count,
            "truncated": ranked.count > hits.count,
            "tasks": rows
        ])
    }

    /// Higher is a better match. Whole-phrase hits beat scattered term hits, and
    /// the description beats the notes — "Cobblestone SW16" should not lose to a
    /// task that merely mentions Cobblestone somewhere in a note.
    private static func matchScore(_ e: Entry, query: String, terms: [String], client clientName: String) -> Int {
        let name = CoachToolFormat.name(e).lowercased()
        let service = e.service.lowercased()
        let client = clientName.lowercased()
        let notes = e.notes.lowercased()

        var score = 0
        if name == query { score += 100 }
        if name.contains(query) { score += 40 }
        if client.contains(query) { score += 20 }

        for term in terms where term.count > 1 {
            if name.contains(term)    { score += 10 }
            if client.contains(term)  { score += 8 }
            if service.contains(term) { score += 4 }
            if notes.contains(term)   { score += 2 }
        }
        return score
    }

    // MARK: - getTaskDetail

    private static func getTaskDetail(_ call: CoachToolCall, _ context: ModelContext) -> String {
        let resolver = EntryResolver(context)
        guard let id = call.string("taskId"), let e = resolver.entry(id) else {
            return json(["error": "No task found for that id. Use findTasks to look it up."])
        }

        let subs = childSubtasks(context)[e.persistentModelID] ?? []
        let logs = childTimeLogs(context)[e.persistentModelID] ?? []

        var out: [String: Any] = [
            "id": e.coachID ?? "",
            "client": clientName(e, clientNames(context)),
            "description": CoachToolFormat.name(e),
            "service": e.service,
            "status": statusKey(e.status),
            "service_date": dayString(e.serviceDate),
            "created": dayString(e.createdAt),
            "hours_logged": round2(e.hours),
            "rate": e.rate,
            "amount": round2(e.hours * e.rate),
            "starred": e.isImportant,
            "invoiced": e.invoice != nil,
            "quick_capture": e.isQuickAdd,
            "timer_running": e.timerStartedAt != nil
        ]
        if let due = e.dueDate { out["due_date"] = dayString(due) }
        if let done = e.completedAt { out["completed"] = dayString(done) }
        if !e.notes.isEmpty { out["notes"] = e.notes }
        if e.expenseAmount > 0 {
            out["expense"] = ["amount": round2(e.expenseAmount), "total": round2(e.expenseTotal)]
        }
        out["subtasks"] = subs.map {
            ["title": $0.title, "done": $0.isDone, "hours": round2($0.hours)] as [String: Any]
        }
        out["time_logs"] = logs.map {
            ["date": dayString($0.addedAt), "hours": round2($0.hours), "note": $0.note] as [String: Any]
        }
        return json(out)
    }

    // MARK: - listClients

    /// The join table between the outside world and BrickDot. Clients come from
    /// a fetch, so every row returned exists — no relationship dereference, no
    /// invalidated-model hazard.
    private static func listClients(_ call: CoachToolCall, _ context: ModelContext) -> String {
        var clients = (try? context.fetch(
            FetchDescriptor<Client>(sortBy: [SortDescriptor(\Client.name)])
        )) ?? []

        if let query = call.string("query")?.lowercased(), !query.isEmpty {
            clients = clients.filter {
                $0.name.lowercased().contains(query) || $0.shortcode.lowercased().contains(query)
            }
        }

        let rows: [[String: Any]] = clients.map { client in
            var row: [String: Any] = ["name": client.name, "rate": client.rate]
            if !client.shortcode.isEmpty { row["shortcode"] = client.shortcode }
            if !client.contactName.isEmpty { row["contact"] = client.contactName }
            if !client.email.isEmpty { row["email"] = client.email }
            if !client.phone.isEmpty { row["phone"] = client.phone }
            return row
        }
        return json(["client_count": rows.count, "clients": rows])
    }

    // MARK: - getClientSummary

    private static func getClientSummary(_ call: CoachToolCall, _ context: ModelContext) -> String {
        let cal = Calendar.current
        let until = call.string("until").flatMap(CoachToolFormat.parseDate) ?? Date()
        let since = call.string("since").flatMap(CoachToolFormat.parseDate)
            ?? cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date()))!
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: until)) ?? until

        var entries = ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { $0.serviceDate >= since && $0.serviceDate < end }

        let names = clientNames(context)
        if let name = call.string("client")?.lowercased(), !name.isEmpty {
            entries = entries.filter { clientName($0, names).lowercased().contains(name) }
        }

        let grouped = Dictionary(grouping: entries, by: { clientName($0, names) })
        let clients: [[String: Any]] = grouped
            .map { name, es in
                let amount = es.reduce(0.0) { $0 + ($1.hours * $1.rate) }
                let uninvoiced = es.filter { $0.invoice == nil }
                return [
                    "client": name,
                    "hours": round2(es.reduce(0.0) { $0 + $1.hours }),
                    "amount": round2(amount),
                    "uninvoiced_hours": round2(uninvoiced.reduce(0.0) { $0 + $1.hours }),
                    "uninvoiced_amount": round2(uninvoiced.reduce(0.0) { $0 + ($1.hours * $1.rate) }),
                    "tasks_open": es.filter { $0.status != .done }.count,
                    "tasks_done": es.filter { $0.status == .done }.count
                ]
            }
            .sorted { ($0["amount"] as? Double ?? 0) > ($1["amount"] as? Double ?? 0) }

        return json([
            "since": dayString(since),
            "until": dayString(until),
            "clients": clients
        ])
    }

    // MARK: - Safe client + child access

    /// Client names keyed by id, read from freshly fetched Clients.
    ///
    /// `entry.client?.name` is not safe: the relationship can hold a Client
    /// whose backing row is gone (a delete merged in from another device, or a
    /// mirroring delegate working from an expired history token), and reading
    /// any stored property off it traps. Identity reads stay safe on such a
    /// model, so we go through `persistentModelID` and look the name up here.
    private static func clientNames(_ context: ModelContext) -> [PersistentIdentifier: String] {
        let all = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return Dictionary(all.map { ($0.persistentModelID, $0.name) },
                          uniquingKeysWith: { first, _ in first })
    }

    private static func clientName(_ e: Entry, _ names: [PersistentIdentifier: String]) -> String {
        if e.setupAction != nil { return "Getting Started" }
        guard let id = e.client?.persistentModelID else { return "Unknown" }
        return names[id] ?? "Unknown"
    }

    private static func childSubtasks(_ context: ModelContext) -> [PersistentIdentifier: [Subtask]] {
        let all = (try? context.fetch(FetchDescriptor<Subtask>(sortBy: [SortDescriptor(\Subtask.createdAt)]))) ?? []
        return Dictionary(grouping: all.filter { $0.parent != nil },
                          by: { $0.parent!.persistentModelID })
    }

    private static func childTimeLogs(_ context: ModelContext) -> [PersistentIdentifier: [TimeLog]] {
        let all = (try? context.fetch(
            FetchDescriptor<TimeLog>(sortBy: [SortDescriptor(\TimeLog.addedAt, order: .reverse)])
        )) ?? []
        return Dictionary(grouping: all.filter { $0.entry != nil },
                          by: { $0.entry!.persistentModelID })
    }

    // MARK: - Helpers

    static func statusKey(_ s: EntryStatus) -> String {
        switch s {
        case .todo:       return "to_do"
        case .inProgress: return "in_progress"
        case .done:       return "done"
        }
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}
