import SwiftUI
import SwiftData

struct NewClientView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query(sort: \Client.name) private var clients: [Client]

    @State private var name: String = ""
    @State private var rate: Double = 0
    @State private var colorIndex: Int = 0
    @State private var shortcode: String = ""
    @State private var isSaving = false

    @FocusState private var focused: Field?
    private enum Field { case name, rate }

    var body: some View {
        Form {
            SwiftUI.Section("New Client") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .name)

                HStack {
                    Text("Rate"); Spacer()
                    TextField("Rate", value: $rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .focused($focused, equals: .rate)
                }
            }

            SwiftUI.Section("Quick Add Shortcode") {
                TextField("e.g. ac, blu, nw", text: $shortcode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("A short abbreviation for quick entry: \"ac design logo 30m\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Color") {
                ClientColorPicker(selectedIndex: $colorIndex)
            }

            SwiftUI.Section {
                Button(action: save) {
                    if isSaving {
                        HStack { ProgressView(); Text("Saving…") }
                    } else {
                        Label("Save Client", systemImage: "tray.and.arrow.down.fill")
                    }
                }
                .disabled(!canSave || isSaving)
            }
        }
        .navigationTitle("New Client")
        .onAppear { colorIndex = ClientColors.nextIndex(existingCount: clients.count) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Prevent duplicate client names
        let exists = clients.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        return !exists
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = Client(name: trimmed, rate: rate, colorIndex: colorIndex)
        client.shortcode = shortcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ctx.insert(client)

        do {
            try ctx.save()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.async { dismiss() }
            isSaving = false
        } catch {
            isSaving = false
        }
    }
}
