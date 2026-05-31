import Foundation
import SwiftData

@Model
final class Subtask {
    var title: String = ""
    var hours: Double = 0
    var isDone: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()

    var parent: Entry?

    init(title: String = "",
         parent: Entry? = nil,
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
