import SwiftData
import SwiftUI

@Model
final class UserProfile {
    var displayName: String = ""
    var companyName: String = ""
    var email: String = ""
    var phone: String = ""
    var addressLine1: String = ""
    var addressLine2: String = ""
    var city: String = ""
    var state: String = ""
    var zip: String = ""

    /// Company logo stored as PNG data (optional)
    @Attribute(.externalStorage)
    var logoData: Data? = nil

    init() {}

    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    static func fetchOrCreate(in context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        return profile
    }
}
