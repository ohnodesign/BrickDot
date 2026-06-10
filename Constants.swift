// Constants.swift
import Foundation

enum Constants {
    private static let defaultServices: [String] = [
        "ADWORD",
        "COMM",
        "CONSULT",
        "DESIGN",
        "EMAIL",
        "HOST",
        "MEDIA",
        "MEET",
        "MISC",
        "PHOTO",
        "PRINT",
        "Sales",
        "SOCIAL",
        "TECHNICAL",
        "WEBCUST",
        "WEBESS",
        "WEBUP"
    ]

    private static let servicesKey = "user.services"

    static var services: [String] {
        get {
            if var saved = UserDefaults.standard.stringArray(forKey: servicesKey) {
                // Migrate: ensure COMM is present for existing users
                if !saved.contains("COMM") {
                    saved.append("COMM")
                    saved.sort()
                    UserDefaults.standard.set(saved, forKey: servicesKey)
                }
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
