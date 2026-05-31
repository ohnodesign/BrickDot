import SwiftUI

struct ProfileView: View {
    @AppStorage("user.displayName") private var displayName = ""

    var body: some View {
        List {
            Section("Your Name") {
                TextField("Enter your name", text: $displayName)
            }

            Section("Account") {
                NavigationLink("Settings") { SettingsView() }
            }

            Section("About") {
                NavigationLink("About This App") { AboutView() }
            }
        }
        .navigationTitle("Profile")
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("App")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionString())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links") {
                Link("Support", destination: URL(string: "https://ohnodesign.com/support")!)
                Link("Privacy", destination: URL(string: "https://ohnodesign.com/privacy")!)
                Link("Website", destination: URL(string: "https://ohnodesign.com")!)
            }
        }
        .navigationTitle("About")
    }

    private func versionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}
