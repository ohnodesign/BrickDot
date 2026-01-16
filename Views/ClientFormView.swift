import SwiftUI
import SwiftData

struct ClientFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    var client: Client?

    @State private var name: String
    @State private var rateString: String
    @State private var alertMsg: String?

    // Focus handling so we can dismiss the keyboard
    @FocusState private var focusedField: Field?
    private enum Field { case name, rate }

    init(client: Client? = nil) {
        self.client = client
        _name = State(initialValue: client?.name ?? "")
        _rateString = State(initialValue: client.map { String(format: "%.2f", $0.rate) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)

                    TextField("Hourly rate", text: $rateString)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .rate)
                }
            }
            .navigationTitle(client == nil ? "New Client" : "Edit Client")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                // DONE button above the number/decimal keyboard
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .alert("Could not save", isPresented: .constant(alertMsg != nil)) {
                Button("OK") { alertMsg = nil }
            } message: { Text(alertMsg ?? "") }
            .onAppear { focusedField = .name }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Double(rateString.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = Double(rateString.replacingOccurrences(of: ",", with: ".")) ?? 0
        do {
            if let client {
                client.name = trimmed
                client.rate = rate
            } else {
                ctx.insert(Client(name: trimmed, rate: rate))
            }
            try ctx.save()
            focusedField = nil
            dismiss()
        } catch {
            let s = String(describing: error).lowercased()
            alertMsg = (s.contains("unique") || s.contains("constraint"))
                ? "That name is already in use."
                : (error.localizedDescription.isEmpty ? "Unknown save error." : error.localizedDescription)
        }
    }
}
