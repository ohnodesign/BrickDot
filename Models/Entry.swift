import Foundation
import SwiftData

@Model
final class Entry {
    // …your existing stored properties…
    var serviceDate: Date
    var service: String
    var detail: String
    var notes: String = ""      // ← NEW: long-form notes for context
    var hours: Double
    var rate: Double
    var client: Client
    var invoice: Invoice?
    var status: EntryStatus
    var timerStartedAt: Date?
    var isImportant: Bool = false
    var isQuickCapture: Bool = false

    // Timestamps
    var createdAt: Date = Date()
    var completedAt: Date? = nil

    // Per-entry time logs (increments)
    @Relationship(deleteRule: .cascade)
    var timeLogs: [TimeLog] = []

    // 👇 MUST live here (not in an extension)
    var subtasks: [Subtask] = []

    init(serviceDate: Date,
         service: String,
         detail: String,
         hours: Double,
         rate: Double,
         client: Client,
         status: EntryStatus = .todo,
         timerStartedAt: Date? = nil,
         createdAt: Date = Date(),
         completedAt: Date? = nil,
         invoice: Invoice? = nil,
         isImportant: Bool = false,
         notes: String = "",     // ← NEW: default empty
         isQuickCapture: Bool = false
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
        self.isQuickCapture = isQuickCapture
    }
}
