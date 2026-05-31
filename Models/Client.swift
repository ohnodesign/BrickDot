import SwiftData

@Model
final class Client {
    var name: String = ""
    var rate: Double = 0
    @Relationship(deleteRule: .cascade, inverse: \Entry.client)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \EntryTemplate.client)
    var templates: [EntryTemplate]? = []
    @Relationship(deleteRule: .cascade, inverse: \Invoice.client)
    var invoices: [Invoice]? = []
    var entriesList: [Entry] {
        get { entries ?? [] }
        set { entries = newValue }
    }
    var templatesList: [EntryTemplate] {
        get { templates ?? [] }
        set { templates = newValue }
    }
    var invoicesList: [Invoice] {
        get { invoices ?? [] }
        set { invoices = newValue }
    }
    init(name: String = "", rate: Double = 0) { self.name = name; self.rate = rate }
}

extension Client: Equatable, Hashable {
    static func == (lhs: Client, rhs: Client) -> Bool {
        lhs.persistentModelID == rhs.persistentModelID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(persistentModelID)
    }
}
