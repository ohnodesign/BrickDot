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

    /// Live subtasks for an entry, fetched rather than read off
    /// `entry.subtasksList`. The relationship array is cached on the Entry and
    /// can still hold a row CloudKit has already deleted elsewhere; that model
    /// is invalidated and reading `title` off it traps.
    func subtasks(of entry: Entry) -> [Subtask] {
        let all = (try? context.fetch(FetchDescriptor<Subtask>(sortBy: [SortDescriptor(\Subtask.createdAt)]))) ?? []
        let id = entry.persistentModelID
        return all.filter { $0.parent?.persistentModelID == id }
    }

    func findByDescription(_ description: String) -> Entry? {
        let open = ((try? context.fetch(FetchDescriptor<Entry>(predicate: Entry.workOnlyPredicate))) ?? []).filter { $0.status != .done }
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

        // --- Single-task tools (the loop's bread and butter) ---
        case "addTime":
            guard let e = resolver.entry(call.string("taskId") ?? "") else { return notFoundID }
            guard let minutes = call.double("minutes"), minutes != 0 else {
                return "No amount of time was specified."
            }
            let hours = minutes / 60
            let when = call.string("date").flatMap(CoachToolFormat.parseDate) ?? Date()
            let log = TimeLog(addedAt: when, hours: hours, note: call.string("note") ?? "", entry: e)
            context.insert(log)
            e.timeLogsList.append(log)
            e.hours += hours
            // An explicit date means the work happened that day, so move the
            // entry with it — otherwise it lands in the wrong week on reports.
            if call.string("date") != nil { e.serviceDate = when }
            e.markModified()
            return "Logged \(CoachToolFormat.duration(minutes)) to \"\(CoachToolFormat.name(e))\" on \(CoachToolFormat.day(when)). Task total is now \(CoachToolFormat.duration(e.hours * 60))."

        case "addSubtask":
            guard let e = resolver.entry(call.string("taskId") ?? "") else { return notFoundID }
            let title = (call.string("title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return "A subtask needs a title." }
            let done = call.bool("done") ?? false
            let sub = Subtask(title: title,
                              parent: e,
                              hours: (call.double("minutes") ?? 0) / 60,
                              isDone: done,
                              completedAt: done ? Date() : nil)
            context.insert(sub)
            e.subtasksList.append(sub)
            e.markModified()
            return "Added subtask \"\(title)\"\(done ? " (done)" : "") to \"\(CoachToolFormat.name(e))\"."

        case "updateSubtask":
            guard let e = resolver.entry(call.string("taskId") ?? "") else { return notFoundID }
            let title = (call.string("title") ?? "").lowercased()
            guard let sub = resolver.subtasks(of: e).first(where: {
                $0.title.lowercased() == title || $0.title.lowercased().contains(title)
            }) else {
                return "No subtask matching \"\(call.string("title") ?? "")\" on that task."
            }
            let done = call.bool("done") ?? true
            sub.isDone = done
            sub.completedAt = done ? Date() : nil
            e.markModified()
            return "Marked subtask \"\(sub.title)\" as \(done ? "done" : "not done")."

        case "createTask":
            let name = (call.string("client") ?? "").lowercased()
            let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
            guard let client = clients.first(where: { $0.name.lowercased() == name })
                    ?? clients.first(where: { $0.name.lowercased().contains(name) && !name.isEmpty }) else {
                let known = clients.map(\.name).sorted().joined(separator: ", ")
                return "No client matching \"\(call.string("client") ?? "")\". Known clients: \(known)."
            }
            let detail = (call.string("description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else { return "A task needs a description." }
            let status = call.string("status").flatMap(CoachToolFormat.statusFrom) ?? .todo
            let minutes = call.double("minutes") ?? 0
            let entry = Entry(
                serviceDate: Date(),
                service: call.string("service") ?? Constants.services.first ?? "",
                detail: detail,
                hours: minutes / 60,
                rate: client.rate > 0 ? client.rate : Constants.defaultRate,
                client: client,
                status: status,
                completedAt: status == .done ? Date() : nil,
                dueDate: call.string("dueDate").flatMap(CoachToolFormat.parseDate)
            )
            // A task created without a stated status is an unreviewed note, which
            // is exactly what Quick Capture is for — it gets a badge and its own
            // section rather than sinking into the general list. Naming a status
            // means it has already been thought about, so file it normally.
            // markModified() clears the flag on the first real edit.
            entry.isQuickAdd = call.bool("quickCapture") ?? (call.string("status") == nil)
            context.insert(entry)
            if minutes > 0 {
                let log = TimeLog(hours: minutes / 60, entry: entry)
                context.insert(log)
                entry.timeLogsList.append(log)
            }
            let logged = minutes > 0 ? " with \(CoachToolFormat.duration(minutes)) logged" : ""
            let filed = entry.isQuickAdd ? " Filed under Quick Captures." : ""
            return "Created \"\(detail)\" for \(client.name)\(logged).\(filed)"

        case "createClient":
            let name = (call.string("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return "A client needs a name." }
            let existing = (try? context.fetch(FetchDescriptor<Client>())) ?? []
            if let clash = existing.first(where: { $0.name.lowercased() == name.lowercased() }) {
                return "\"\(clash.name)\" already exists — use it rather than creating a second one."
            }
            let client = Client(name: name,
                                rate: call.double("rate") ?? Constants.defaultRate,
                                colorIndex: existing.count % 8)
            client.shortcode = call.string("shortcode") ?? ""
            client.contactName = call.string("contactName") ?? ""
            client.email = call.string("email") ?? ""
            client.phone = call.string("phone") ?? ""
            client.address = call.string("address") ?? ""
            context.insert(client)
            return "Created client \"\(client.name)\" at \(CoachToolFormat.money(client.rate))/hr."

        case "createInvoice":
            let wanted = (call.string("client") ?? "").lowercased()
            let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
            guard let client = clients.first(where: { $0.name.lowercased() == wanted })
                    ?? clients.first(where: { !wanted.isEmpty && $0.name.lowercased().contains(wanted) }) else {
                return "No client matching \"\(call.string("client") ?? "")\"."
            }

            // Fetch and filter by id rather than walking client.entriesList — the
            // relationship array can hold rows CloudKit has already removed.
            let clientID = client.persistentModelID
            let all = (try? context.fetch(FetchDescriptor<Entry>(predicate: Entry.workOnlyPredicate))) ?? []
            var billable: [Entry]

            let ids = call.stringArray("taskIds")
            if !ids.isEmpty {
                billable = resolver.entries(ids).filter { $0.invoice == nil }
            } else {
                billable = all.filter { $0.client?.persistentModelID == clientID && $0.invoice == nil }
                if let since = call.string("since").flatMap(CoachToolFormat.parseDate) {
                    billable = billable.filter { $0.serviceDate >= since }
                }
                if let until = call.string("until").flatMap(CoachToolFormat.parseDate),
                   let end = Calendar.current.date(byAdding: .day, value: 1, to: until) {
                    billable = billable.filter { $0.serviceDate < end }
                }
            }

            guard !billable.isEmpty else {
                return "Nothing uninvoiced for \(client.name) in that range."
            }

            let base = call.string("title") ?? CoachToolFormat.invoiceTitle(for: billable)
            let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
            let sameClient = invoices.filter { $0.client?.persistentModelID == clientID }
            let clashes = sameClient.filter { $0.title.hasPrefix(base) }.count
            let title = clashes == 0 ? base : "\(base) \(clashes + 1)"

            // Consumes the next number in the sequence — not reversible.
            let number = InvoiceNumberManager.nextAndAdvance()
            let invoice = Invoice(title: title, number: number, client: client)
            context.insert(invoice)
            invoice.entriesList.append(contentsOf: billable)

            let hours = billable.reduce(0.0) { $0 + $1.hours }
            let amount = billable.reduce(0.0) { $0 + ($1.hours * $1.rate) }
            return "Created invoice \(number) for \(client.name) — \(billable.count) item\(billable.count == 1 ? "" : "s"), \(CoachToolFormat.duration(hours * 60)), \(CoachToolFormat.money(amount)). Render the PDF from the Export screen."

        case "startTimer":
            guard let e = resolver.entry(call.string("taskId") ?? "") else { return notFoundID }
            e.status = .inProgress
            e.completedAt = nil
            if e.timerStartedAt == nil { e.timerStartedAt = Date() }
            return "Started the timer on \"\(CoachToolFormat.name(e))\"."

        case "stopTimer":
            guard let e = resolver.entry(call.string("taskId") ?? "") else { return notFoundID }
            guard let started = e.timerStartedAt else { return "No timer is running on that task." }
            let elapsed = Date().timeIntervalSince(started) / 3600
            let log = TimeLog(hours: elapsed, entry: e)
            context.insert(log)
            e.timeLogsList.append(log)
            e.hours += elapsed
            e.timerStartedAt = nil
            return "Stopped the timer on \"\(CoachToolFormat.name(e))\" — logged \(CoachToolFormat.duration(elapsed * 60))."

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

    private static var notFoundID: String {
        "Couldn't find that task. Use findTasks to look up its id first."
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

    /// "2h", "2h 30m", "45 min" — reads back naturally in a chat reply.
    static func duration(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    static func money(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// Mirrors the Export screen's naming so invoices made here sit alongside
    /// the ones made by hand without looking foreign.
    static func invoiceTitle(for entries: [Entry]) -> String {
        let dates = entries.map(\.serviceDate).sorted()
        guard let first = dates.first, let last = dates.last else { return "Invoice" }
        let month = DateFormatter()
        month.dateFormat = "yyyy-MM"
        month.locale = Locale(identifier: "en_US_POSIX")
        let a = month.string(from: first)
        let b = month.string(from: last)
        return a == b ? "\(a) Invoice" : "\(a)-\(b) Invoice"
    }

    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
