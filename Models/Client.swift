import SwiftData

@Model
final class Client {
    var name: String = ""
    var rate: Double = 0
    @Relationship(deleteRule: .cascade, inverse: \Entry.client)
    var entries: [Entry] = []
    @Relationship(deleteRule: .cascade, inverse: \EntryTemplate.client)
    var templates: [EntryTemplate] = []
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
