// Models/Invoice.swift
import Foundation
import SwiftData

@Model
final class Invoice {
    var title: String
    var number: String?       // optional if you want to auto-assign
    var createdAt: Date
    var client: Client

    // relationship back to entries
    @Relationship(deleteRule: .noAction, inverse: \Entry.invoice)
    var entries: [Entry] = []

    init(title: String, number: String? = nil, createdAt: Date = Date(), client: Client) {
        self.title = title
        self.number = number
        self.createdAt = createdAt
        self.client = client
    }
}
