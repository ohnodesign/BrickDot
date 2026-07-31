import Foundation
import SwiftData

/// Builds the Coach task payload on a background context. Serializing every
/// entry — and encoding each one's persistent id (coachID) — is too heavy to run
/// on the main thread on every send; doing it here keeps the UI responsive. The
/// resulting id strings are global persistent ids, so they still resolve against
/// the main context at Apply time.
@ModelActor
actor PayloadBuilder {
    func build() -> String {
        TaskDataSerializer.buildPayload(context: modelContext)
    }
}

/// Applies confirmed Coach changes against a ModelContext. Runs on the main
/// context — the same path the task editor uses to change a single field, which
/// saves cleanly. (An earlier off-main background-actor version forced a
/// cross-context CloudKit merge back into the main context; matching the editor
/// avoids that.) Tasks are located by `coachID`, a value derived from the
/// SwiftData persistent id, so there is no stored id field and no record churn.
/// Resolves AI tool-call task ids back to Entry objects. The id is the
/// base64-encoded SwiftData persistent id; we DECODE it to a PersistentIdentifier
/// and resolve it with `ModelContext.model(for:)`. (A decoded PersistentIdentifier
/// is NOT == / hash-equal to the live one from a fetch, so a dictionary keyed on
/// the identifier silently misses every time — `model(for:)` resolves by primary
/// key and works.)
struct EntryResolver {
    private let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    func entry(_ idString: String) -> Entry? {
        guard let data = Data(base64Encoded: idString),
              let pid = try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
        else { return nil }
        return context.model(for: pid) as? Entry
    }

    func entries(_ ids: [String]) -> [Entry] {
        ids.compactMap { entry($0) }
    }

    func findByDescription(_ description: String) -> Entry? {
        let open = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { $0.status != .done }
        let query = description.lowercased()
        if let exact = open.first(where: {
            $0.detail.lowercased() == query || $0.service.lowercased() == query
        }) {
            return exact
        }
        return open.first(where: {
            $0.detail.lowercased().contains(query) ||
            $0.service.lowercased().contains(query) ||
            query.contains($0.detail.lowercased()) ||
            query.contains($0.service.lowercased())
        })
    }
}

enum CoachToolExecutor {

    static func execute(_ call: CoachToolCall, context: ModelContext) -> String {
        let resolver = EntryResolver(context)

        switch call.name {

        // --- ID-based tools ---
        case "starTasks":
            let es = resolver.entries(call.stringArray("taskIds"))
            guard !es.isEmpty else { return "Couldn't find those tasks." }
            es.forEach { $0.isImportant = true }
            return "Starred \(label(es))."

        case "unstarTasks":
            let es = resolver.entries(call.stringArray("taskIds"))
            guard !es.isEmpty else { return "Couldn't find those tasks." }
            es.forEach { $0.isImportant = false }
            return "Unstarred \(label(es))."

        case "updateDueDate":
            let es = resolver.entries(call.stringArray("taskIds"))
            guard !es.isEmpty else { return "Couldn't find those tasks." }
            if let shift = call.string("shift") {
                let date = CoachToolFormat.resolveShift(shift)
                es.forEach { $0.dueDate = date }
                return "Set due date for \(label(es)) to \(CoachToolFormat.shiftLabel(shift))."
            } else if let ds = call.string("dueDate"), let d = CoachToolFormat.parseDate(ds) {
                es.forEach { $0.dueDate = d }
                return "Set due date for \(label(es)) to \(ds)."
            }
            return "No due date change was specified."

        case "updateTaskStatus":
            let es = resolver.entries(call.stringArray("taskIds"))
            guard let raw = call.string("status"), let status = CoachToolFormat.statusFrom(raw) else {
                return "Unknown status."
            }
            guard !es.isEmpty else { return "Couldn't find those tasks." }
            es.forEach { apply(status, to: $0) }
            return "Marked \(label(es)) as \(CoachToolFormat.statusLabel(status))."

        case "bulkUpdate":
            var count = 0
            for u in call.objectArray("updates") {
                guard let tid = u["taskId"] as? String, let e = resolver.entry(tid) else { continue }
                if let v = u["star"] as? Bool, v { e.isImportant = true }
                if let v = u["unstar"] as? Bool, v { e.isImportant = false }
                if let st = u["status"] as? String, let s = CoachToolFormat.statusFrom(st) { apply(s, to: e) }
                if let sh = u["shift"] as? String {
                    e.dueDate = CoachToolFormat.resolveShift(sh)
                } else if let ds = u["dueDate"] as? String, let d = CoachToolFormat.parseDate(ds) {
                    e.dueDate = d
                }
                count += 1
            }
            return "Applied \(count) change\(count == 1 ? "" : "s")."

        // --- Legacy, description-matched tools ---
        case "start_timer":
            guard let e = resolver.findByDescription(call.string("task_description") ?? "") else { return notFound(call) }
            e.status = .inProgress
            if e.timerStartedAt == nil { e.timerStartedAt = Date() }
            return "Started timer on \"\(CoachToolFormat.name(e))\"."

        case "stop_timer":
            guard let e = resolver.findByDescription(call.string("task_description") ?? "") else { return notFound(call) }
            guard let started = e.timerStartedAt else { return "No timer running on that task." }
            let elapsed = Date().timeIntervalSince(started) / 3600
            e.hours += elapsed
            e.timeLogsList.append(TimeLog(hours: elapsed, entry: e))
            e.timerStartedAt = nil
            return "Stopped timer on \"\(CoachToolFormat.name(e))\" — logged \(Int(elapsed * 60)) min."

        case "mark_done":
            guard let e = resolver.findByDescription(call.string("task_description") ?? "") else { return notFound(call) }
            apply(.done, to: e)
            return "Marked \"\(CoachToolFormat.name(e))\" as done."

        case "add_time":
            guard let e = resolver.findByDescription(call.string("task_description") ?? "") else { return notFound(call) }
            let minutes = Double(call.string("minutes") ?? "0") ?? 0
            let hours = minutes / 60
            e.hours += hours
            e.timeLogsList.append(TimeLog(hours: hours, entry: e))
            return "Added \(Int(minutes)) min to \"\(CoachToolFormat.name(e))\"."

        case "set_priority":
            guard let e = resolver.findByDescription(call.string("task_description") ?? "") else { return notFound(call) }
            let isHigh = call.string("priority") == "high"
            e.isImportant = isHigh
            return "Set \"\(CoachToolFormat.name(e))\" to \(isHigh ? "high" : "normal") priority."

        default:
            return "Unknown action."
        }
    }

    private static func apply(_ status: EntryStatus, to e: Entry) {
        e.status = status
        if status == .done {
            e.completedAt = Date()
            e.timerStartedAt = nil
        } else {
            e.completedAt = nil
        }
    }

    private static func label(_ entries: [Entry]) -> String {
        let names = entries.map { CoachToolFormat.name($0) }
        if names.count == 1 { return "\"\(names[0])\"" }
        if names.count <= 3 { return names.map { "\"\($0)\"" }.joined(separator: ", ") }
        return "\(names.count) tasks"
    }

    private static func notFound(_ call: CoachToolCall) -> String {
        "Could not find a task matching \"\(call.string("task_description") ?? "")\"."
    }
}

/// Pure, context-free helpers shared by the executor and the view's summaries.
enum CoachToolFormat {
    static func name(_ e: Entry) -> String { e.detail.isEmpty ? e.service : e.detail }

    static func statusFrom(_ raw: String) -> EntryStatus? {
        switch raw.lowercased() {
        case "to_do", "todo", "open": return .todo
        case "in_progress", "inprogress": return .inProgress
        case "done", "complete", "completed": return .done
        default: return nil
        }
    }

    static func statusLabel(_ status: EntryStatus) -> String {
        switch status {
        case .todo: return "to do"
        case .inProgress: return "in progress"
        case .done: return "done"
        }
    }

    static func shiftLabel(_ shift: String) -> String {
        switch shift {
        case "tomorrow": return "tomorrow"
        case "nextWeek": return "next week"
        case "clear": return "no due date"
        default: return shift
        }
    }

    static func resolveShift(_ shift: String) -> Date? {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        switch shift {
        case "tomorrow": return cal.date(byAdding: .day, value: 1, to: base)
        case "nextWeek": return cal.date(byAdding: .weekOfYear, value: 1, to: base)
        default: return nil   // "clear" or unknown → remove the due date
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
