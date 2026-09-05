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

    /// True when this invoice came in from a QuickBooks CSV import rather than
    /// being built in the app. Its entries are billing records (see
    /// `Entry.isBillingRecord`) and stay out of the regular lists.
    var isImported: Bool = false

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

    /// Sum of the invoice's line items.
    var total: Double {
        entriesList.reduce(0) { $0 + $1.hours * $1.rate + $1.expenseTotal }
    }

    var totalHours: Double {
        entriesList.reduce(0) { $0 + $1.hours }
    }

    init(title: String = "", number: String? = nil, createdAt: Date = Date(), client: Client? = nil, isImported: Bool = false) {
        self.title = title
        self.number = number
        self.createdAt = createdAt
        self.client = client
        self.isImported = isImported
    }
}
