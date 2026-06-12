import SwiftUI
import SwiftData

struct ClientListView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var searchText: String = ""
    @State private var showNewClient: Bool = false
    @State private var showNewEntry: Bool = false
    @State private var newEntryPrefillClient: Client? = nil
    @State private var clientToDelete: Client? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            if filteredClients.isEmpty {
                if clients.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(theme.accent)
                        Text("No clients yet")
                            .font(.headline)
                        Text("Clients are who you bill. Every entry, timer, and invoice hangs off one — and their rate fills in automatically.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showNewClient = true
                        } label: {
                            Label("Add Your First Client", systemImage: "plus")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowSeparator(.hidden)
                } else {
                    Text("No clients match “\(searchText)”")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredClients, id: \.persistentModelID) { c in
                    NavigationLink {
                        ClientDetailView(client: c)   // ← fixed type name
                    } label: {
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button {
                            newEntryPrefillClient = c
                            showNewEntry = true
                        } label: {
                            Label("New Entry for \(c.name)", systemImage: "plus.circle")
                        }
                    }
                }
                .onDelete { offsets in
                    if let idx = offsets.first {
                        clientToDelete = filteredClients[idx]
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewClient = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(Color(.darkGray))
                }
                .accessibilityLabel("New Client")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .sheet(isPresented: $showNewClient) {
            NavigationStack { NewClientView() }
        }
        .sheet(isPresented: $showNewEntry) {
            QuickAddView(
                prefillClient: newEntryPrefillClient,
                onSaved: { showNewEntry = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete \(clientToDelete?.name ?? "Client")?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let c = clientToDelete {
                    ctx.delete(c)
                    try? ctx.save()
                }
                clientToDelete = nil
            }
            Button("Cancel", role: .cancel) { clientToDelete = nil }
        } message: {
            if let c = clientToDelete {
                Text("This will permanently delete \(c.name) and all associated entries, invoices, and templates.")
            }
        }
    }

    private var filteredClients: [Client] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(s) }
    }

}

