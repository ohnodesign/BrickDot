import Foundation
import SwiftData

@Model
final class TimeLog {
    var addedAt: Date
    var hours: Double
    var note: String

    // Relationship back to the owning entry
    @Relationship(deleteRule: .noAction)
    var entry: Entry

    init(addedAt: Date = Date(), hours: Double, note: String = "", entry: Entry) {
        self.addedAt = addedAt
        self.hours = hours
        self.note = note
        self.entry = entry
    }
}
