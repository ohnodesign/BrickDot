import SwiftData

@Model
final class Client {
    @Attribute(.unique) var name: String
    var rate: Double
    @Relationship(deleteRule: .cascade, inverse: \Entry.client)
    var entries: [Entry] = []
    init(name: String, rate: Double) { self.name = name; self.rate = rate }
}
import SwiftData

extension Client: Equatable, Hashable {
    static func == (lhs: Client, rhs: Client) -> Bool {
        lhs.persistentModelID == rhs.persistentModelID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(persistentModelID)
    }
}
