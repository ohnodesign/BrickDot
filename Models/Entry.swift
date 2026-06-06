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
    var dueDate: Date? = nil
    var billOnCompletion: Bool = false

    var expenseAmount: Double = 0
    var expenseMarkup: Double = 0
    var expenseMarkupIsPercent: Bool = true

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

    var clientName: String { client?.name ?? "Unknown" }
    var clientRate: Double { client?.rate ?? 0 }

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
}
