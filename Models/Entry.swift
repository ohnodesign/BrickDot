import Foundation
import SwiftData

@Model
final class Entry {
    var serviceDate: Date = Date()
    var service: String = ""
    var detail: String = ""
    var notes: String = ""
    var hours: Double = 0
    var rate: Double = 0
    var client: Client?
    var invoice: Invoice?
    var statusRaw: String = "To Do"
    var timerStartedAt: Date?
    var isImportant: Bool = false
    var isQuickAdd: Bool = false
    // First-run starter todo: SetupAction rawValue ("profile", "services", …)
    // that deep-links the row to an app section. Nil for normal entries.
    var setupAction: String? = nil
    var dueDate: Date? = nil
    var billOnCompletion: Bool = false

    var expenseAmount: Double = 0
    var expenseMarkup: Double = 0
    var expenseMarkupIsPercent: Bool = true

    // Communication fields (only used when service == "COMM")
    var commChannel: String? = nil      // "email", "phone", "text", "chat"
    var commDirection: String? = nil    // "needsReply", "awaitingResponse"
    var commContact: String? = nil      // contact name or number

    var expenseTotal: Double {
        if expenseMarkupIsPercent {
            return expenseAmount * (1 + expenseMarkup / 100)
        } else {
            return expenseAmount + expenseMarkup
        }
    }

    var createdAt: Date = Date()
    var completedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \TimeLog.entry)
    var timeLogs: [TimeLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \Subtask.parent)
    var subtasks: [Subtask]? = []

    var status: EntryStatus {
        get { EntryStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    /// Never reads `client?.name` directly — that traps when the Client's row is
    /// gone (a delete merged from another device, or a half-imported store), and
    /// it took down the entry list. Resolved through the store instead, which
    /// only knows about rows that exist. See ClientInfoCache.
    var clientName: String {
        guard let client, let context = modelContext else { return "Unknown" }
        return ClientInfoCache.info(for: client.persistentModelID, in: context)?.name ?? "Unknown"
    }

    /// Round-trippable, session-stable id for AI Coach tool calls, derived from
    /// the SwiftData persistent id. Computed — there is NO stored field, so it
    /// requires no migration and (unlike a stored UUID) never rewrites every
    /// record into CloudKit. Matched by re-deriving it on lookup.
    var coachID: String? {
        (try? JSONEncoder().encode(persistentModelID))?.base64EncodedString()
    }

    /// Row-display name: starter setup todos have no client, so label them
    /// instead of showing "Unknown".
    var displayClientName: String {
        setupAction != nil ? "Getting Started" : clientName
    }
    /// Same hazard as `clientName` — resolved through the store, not the
    /// relationship.
    var clientRate: Double {
        guard let client, let context = modelContext else { return 0 }
        return ClientInfoCache.info(for: client.persistentModelID, in: context)?.rate ?? 0
    }

    // Non-optional accessors for CloudKit-optional arrays
    var timeLogsList: [TimeLog] {
        get { timeLogs ?? [] }
        set { timeLogs = newValue }
    }
    var subtasksList: [Subtask] {
        get { subtasks ?? [] }
        set { subtasks = newValue }
    }

    init(serviceDate: Date = Date(),
         service: String = "",
         detail: String = "",
         hours: Double = 0,
         rate: Double = 0,
         client: Client? = nil,
         status: EntryStatus = .todo,
         timerStartedAt: Date? = nil,
         createdAt: Date = Date(),
         completedAt: Date? = nil,
         invoice: Invoice? = nil,
         isImportant: Bool = false,
         notes: String = "",
         dueDate: Date? = nil,
         billOnCompletion: Bool = false
    ) {
        self.serviceDate = serviceDate
        self.service = service
        self.detail = detail
        self.notes = notes
        self.hours = hours
        self.rate = rate
        self.client = client
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.timerStartedAt = timerStartedAt
        self.invoice = invoice
        self.isImportant = isImportant
        self.dueDate = dueDate
        self.billOnCompletion = billOnCompletion
    }

    /// Any manual change to a Quick Capture entry means it's no longer a raw,
    /// unreviewed capture — unpins it from the Home "Quick Captures" section.
    func markModified() {
        if isQuickAdd {
            isQuickAdd = false
        }
    }
}
