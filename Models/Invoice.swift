// Models/Invoice.swift
import Foundation
import SwiftData

@Model
final class Invoice {
    var title: String = ""
    var number: String?
    var createdAt: Date = Date()
    /// Manual ordering within a client's invoice list. Lower sorts first;
    /// ties fall back to createdAt. Defaults to 0 until the user reorders.
    var sortIndex: Int = 0
    var client: Client?

    @Relationship(deleteRule: .noAction, inverse: \Entry.invoice)
    var entries: [Entry]? = []

    /// Same trap as `Entry.clientName`: reading `client?.name` fatals when the
    /// Client's row has been removed out from under the relationship.
    var safeClientName: String {
        guard let client, let context = modelContext else { return "Unknown" }
        return ClientInfoCache.info(for: client.persistentModelID, in: context)?.name ?? "Unknown"
    }

    var entriesList: [Entry] {
        get { entries ?? [] }
        set { entries = newValue }
    }

    init(title: String = "", number: String? = nil, createdAt: Date = Date(), client: Client? = nil) {
        self.title = title
        self.number = number
        self.createdAt = createdAt
        self.client = client
    }
}
