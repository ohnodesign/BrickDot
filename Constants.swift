// Constants.swift
import Foundation

enum Constants {
    // Generic starter set for new installs. Users add their own in
    // Settings; existing users keep the list saved under servicesKey.
    private static let defaultServices: [String] = [
        "DESIGN",
        "PHOTO",
        "SALES"
    ]

    private static let servicesKey = "user.services"

    static var services: [String] {
        get {
            if let saved = UserDefaults.standard.stringArray(forKey: servicesKey) {
                return saved
            }
            UserDefaults.standard.set(defaultServices, forKey: servicesKey)
            return defaultServices
        }
        set {
            UserDefaults.standard.set(newValue, forKey: servicesKey)
        }
    }

    /// True once the user has changed the service list from the defaults.
    static var servicesCustomized: Bool {
        guard let saved = UserDefaults.standard.stringArray(forKey: servicesKey) else { return false }
        return saved != defaultServices
    }

    static let defaultRate: Double = 125
}
