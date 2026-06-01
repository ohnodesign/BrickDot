import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @State private var profile: UserProfile?

    var body: some View {
        Form {
            if let profile {
                Section("Your Name") {
                    TextField("Full name", text: Binding(
                        get: { profile.displayName },
                        set: { profile.displayName = $0 }
                    ))
                }

                Section("Business") {
                    TextField("Company name", text: Binding(
                        get: { profile.companyName },
                        set: { profile.companyName = $0 }
                    ))
                    TextField("Email", text: Binding(
                        get: { profile.email },
                        set: { profile.email = $0 }
                    ))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    TextField("Phone", text: Binding(
                        get: { profile.phone },
                        set: { profile.phone = $0 }
                    ))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                }

                Section("Address") {
                    TextField("Street", text: Binding(
                        get: { profile.addressLine1 },
                        set: { profile.addressLine1 = $0 }
                    ))
                    .textContentType(.streetAddressLine1)
                    TextField("Suite / Unit", text: Binding(
                        get: { profile.addressLine2 },
                        set: { profile.addressLine2 = $0 }
                    ))
                    .textContentType(.streetAddressLine2)
                    TextField("City", text: Binding(
                        get: { profile.city },
                        set: { profile.city = $0 }
                    ))
                    .textContentType(.addressCity)
                    TextField("State", text: Binding(
                        get: { profile.state },
                        set: { profile.state = $0 }
                    ))
                    .textContentType(.addressState)
                    TextField("ZIP", text: Binding(
                        get: { profile.zip },
                        set: { profile.zip = $0 }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                }
            }

            Section("About") {
                NavigationLink("About This App") { AboutView() }
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            if profile == nil {
                profile = UserProfile.fetchOrCreate(in: ctx)
            }
        }
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
