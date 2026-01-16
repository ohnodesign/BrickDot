import Foundation
import SwiftData

@Model
final class Subtask {
    var title: String
    var hours: Double         // ⏱ time logged for this subtask
    var isDone: Bool          // ✅ checkbox state
    var completedAt: Date?    // 📅 when it was marked done
    var createdAt: Date       // 🕒 audit / sort helper

    // Relationship back to entry
    var parent: Entry

    init(title: String,
         parent: Entry,
         hours: Double = 0,
         isDone: Bool = false,
         completedAt: Date? = nil,
         createdAt: Date = Date()) {
        self.title = title
        self.parent = parent
        self.hours = hours
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
