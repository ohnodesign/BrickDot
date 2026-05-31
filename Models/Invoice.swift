// Models/Invoice.swift
import Foundation
import SwiftData

@Model
final class Invoice {
    var title: String = ""
    var number: String?
    var createdAt: Date = Date()
    var client: Client?

    @Relationship(deleteRule: .noAction, inverse: \Entry.invoice)
    var entries: [Entry]? = []

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
