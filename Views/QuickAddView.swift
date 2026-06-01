import SwiftUI
import SwiftData

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query(sort: \Client.name) private var clients: [Client]

    @State private var selectedClient: Client?
    @State private var service: String = Constants.services.first ?? ""
    @State private var detail: String = ""
    @State private var isSaving = false
    @State private var showFullEntry = false

    // Recall last-used client and service
    @AppStorage("quickadd.lastClientName") private var lastClientName = ""
    @AppStorage("quickadd.lastService") private var lastService = ""

    var prefillClient: Client? = nil
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        // Client picker
                        Picker("Client", selection: $selectedClient) {
                            ForEach(clients, id: \.persistentModelID) { c in
                                Text(c.name).tag(Optional(c))
                            }
                        }

                        // Service picker
                        Picker("Service", selection: $service) {
                            ForEach(Constants.services, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }

                        // Description
                        TextField("What are you working on?", text: $detail)
                            .textInputAutocapitalization(.sentences)
                    }

                    Section {
                        Button(action: save) {
                            if isSaving {
                                HStack { ProgressView(); Text("Saving…") }
                            } else {
                                HStack {
                                    Image(systemName: "bolt.fill")
                                    Text("Quick Save")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                        }
                        .disabled(selectedClient == nil || isSaving)

                        Button {
                            showFullEntry = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.pencil")
                                Text("More Details…")
                                Spacer()
                            }
                            .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let pre = prefillClient {
                    selectedClient = pre
                } else if let last = clients.first(where: { $0.name == lastClientName }) {
                    selectedClient = last
                } else {
                    selectedClient = clients.first
                }
                if !lastService.isEmpty && Constants.services.contains(lastService) {
                    service = lastService
                }
            }
            .sheet(isPresented: $showFullEntry) {
                NavigationStack {
                    NewEntryView(
                        onSaved: {
                            showFullEntry = false
                            onSaved?()
                            dismiss()
                        },
                        prefillClient: selectedClient,
                        prefillService: service,
                        prefillDetail: detail
                    )
                }
            }
        }
    }

    private func save() {
        guard let client = selectedClient, !isSaving else { return }
        isSaving = true

        let entry = Entry(
            serviceDate: Date(),
            service: service,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            hours: 0,
            rate: client.rate,
            client: client,
            status: .todo,
            createdAt: Date()
        )
        ctx.insert(entry)

        do {
            try ctx.save()
            lastClientName = client.name
            lastService = service
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isSaving = false
            onSaved?()
            dismiss()
        } catch {
            isSaving = false
        }
    }
}
