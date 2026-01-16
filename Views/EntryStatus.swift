import Foundation

public enum EntryStatus: String, Codable, CaseIterable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"
}
