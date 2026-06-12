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

    static let defaultRate: Double = 125
}
