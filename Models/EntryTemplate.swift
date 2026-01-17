import Foundation
import SwiftData

@Model
final class EntryTemplate {
    var name: String
    var service: String
    var detail: String
    var notes: String
    var defaultHours: Double
    var client: Client
    var createdAt: Date

    init(
        name: String,
        service: String,
        detail: String = "",
        notes: String = "",
        defaultHours: Double = 0,
        client: Client,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.service = service
        self.detail = detail
        self.notes = notes
        self.defaultHours = defaultHours
        self.client = client
        self.createdAt = createdAt
    }
}
