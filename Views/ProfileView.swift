import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @State private var profile: UserProfile?

    private func saveBinding<T>(_ keyPath: ReferenceWritableKeyPath<UserProfile, T>) -> Binding<T>? {
        guard let profile else { return nil }
        return Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0; try? ctx.save() }
        )
    }

    var body: some View {
        Form {
            if let displayName = saveBinding(\.displayName),
               let companyName = saveBinding(\.companyName),
               let email = saveBinding(\.email),
               let phone = saveBinding(\.phone),
               let addressLine1 = saveBinding(\.addressLine1),
               let addressLine2 = saveBinding(\.addressLine2),
               let city = saveBinding(\.city),
               let state = saveBinding(\.state),
               let zip = saveBinding(\.zip) {
                Section("Your Name") {
                    TextField("Full name", text: displayName)
                }

                Section("Business") {
                    TextField("Company name", text: companyName)
                    TextField("Email", text: email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone", text: phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                Section("Address") {
                    TextField("Street", text: addressLine1)
                        .textContentType(.streetAddressLine1)
                    TextField("Suite / Unit", text: addressLine2)
                        .textContentType(.streetAddressLine2)
                    TextField("City", text: city)
                        .textContentType(.addressCity)
                    TextField("State", text: state)
                        .textContentType(.addressState)
                    TextField("ZIP", text: zip)
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
