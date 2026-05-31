import Foundation
import SwiftData

@Model
final class TimeLog {
    var addedAt: Date = Date()
    var hours: Double = 0
    var note: String = ""

    @Relationship(deleteRule: .noAction)
    var entry: Entry?

    init(addedAt: Date = Date(), hours: Double = 0, note: String = "", entry: Entry? = nil) {
        self.addedAt = addedAt
        self.hours = hours
        self.note = note
        self.entry = entry
    }
}
