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
    var status: EntryStatus = .todo
    var timerStartedAt: Date?
    var isImportant: Bool = false
    var dueDate: Date? = nil
    var billOnCompletion: Bool = false

    var createdAt: Date = Date()
    var completedAt: Date? = nil

    @Relationship(deleteRule: .cascade)
    var timeLogs: [TimeLog] = []

    var subtasks: [Subtask] = []

    // Convenience for views that need a non-optional client name
    var clientName: String { client?.name ?? "Unknown" }
    var clientRate: Double { client?.rate ?? 0 }

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
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.timerStartedAt = timerStartedAt
        self.invoice = invoice
        self.isImportant = isImportant
        self.dueDate = dueDate
        self.billOnCompletion = billOnCompletion
    }
}
