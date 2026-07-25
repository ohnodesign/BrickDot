import SwiftData

@Model
final class Client {
    var name: String = ""
    var rate: Double = 0
    var colorIndex: Int = 0
    var shortcode: String = ""
    var contactName: String = ""
    var address: String = ""
    var phone: String = ""
    var businessPhone: String = ""
    var email: String = ""
    @Relationship(deleteRule: .cascade, inverse: \Entry.client)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \EntryTemplate.client)
    var templates: [EntryTemplate]? = []
    @Relationship(deleteRule: .cascade, inverse: \Invoice.client)
    var invoices: [Invoice]? = []
    // Inverse for SavedSearch.client. CloudKit refuses to load the store if
    // any relationship lacks one. Cascade: a saved search scoped to a
    // deleted client no longer describes anything.
    @Relationship(deleteRule: .cascade, inverse: \SavedSearch.client)
    var savedSearches: [SavedSearch]? = []
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
    var savedSearchesList: [SavedSearch] {
        get { savedSearches ?? [] }
        set { savedSearches = newValue }
    }
    init(name: String = "", rate: Double = 0, colorIndex: Int = 0) {
        self.name = name
        self.rate = rate
        self.colorIndex = colorIndex
    }
}

extension Client: Equatable, Hashable {
    static func == (lhs: Client, rhs: Client) -> Bool {
        lhs.persistentModelID == rhs.persistentModelID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(persistentModelID)
    }
}
