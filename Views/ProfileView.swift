import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [UserProfile]
    @State private var profile: UserProfile?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showRemoveLogoAlert = false

    private func saveBinding<T>(_ keyPath: ReferenceWritableKeyPath<UserProfile, T>) -> Binding<T>? {
        guard let profile else { return nil }
        return Binding(
            get: { profile[keyPath: keyPath] },
            set: { profile[keyPath: keyPath] = $0; try? ctx.save() }
        )
    }

    /// Picks the profile to edit, preferring one that actually has data. This
    /// fixes the reinstall race: an empty profile can be created before
    /// CloudKit syncs the real one down, so once the real record arrives we
    /// switch to it and delete any leftover empty placeholder. Only creates a
    /// new profile when there genuinely isn't one anywhere.
    private func resolveProfile() {
        if let populated = profiles.first(where: { $0.hasContent }) {
            profile = populated
            for p in profiles where p !== populated && !p.hasContent {
                ctx.delete(p)
            }
            try? ctx.save()
        } else if let existing = profiles.first {
            profile = existing
        } else if profile == nil {
            let p = UserProfile()
            ctx.insert(p)
            profile = p
        }
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

                // Logo upload
                Section("Company Logo") {
                    if let logoData = profile?.logoData, let uiImage = UIImage(data: logoData) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Spacer()

                            VStack(spacing: 8) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Replace", systemImage: "photo")
                                        .font(.caption)
                                }

                                Button(role: .destructive) {
                                    showRemoveLogoAlert = true
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(.caption)
                                }
                            }
                        }
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add Logo")
                                        .font(.body.weight(.medium))
                                    Text("Appears on PDF invoices")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

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
        .onAppear { resolveProfile() }
        .onChange(of: profiles.count) { _, _ in resolveProfile() }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let item else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Resize to a reasonable max for logo (max 600px wide)
                    if let image = UIImage(data: data), let resized = resizeLogo(image, maxWidth: 600) {
                        profile?.logoData = resized
                        try? ctx.save()
                    }
                }
                selectedPhoto = nil
            }
        }
        .alert("Remove Logo?", isPresented: $showRemoveLogoAlert) {
            Button("Remove", role: .destructive) {
                profile?.logoData = nil
                try? ctx.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The logo will be removed from your profile and invoices.")
        }
    }

    /// Resize image to a max width, preserving aspect ratio, and return PNG data.
    private func resizeLogo(_ image: UIImage, maxWidth: CGFloat) -> Data? {
        let scale = min(1.0, maxWidth / image.size.width)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.pngData()
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
