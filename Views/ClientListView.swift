import SwiftUI
import SwiftData

struct ClientListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var searchText: String = ""
    @State private var showNewClient: Bool = false
    @State private var showNewEntry: Bool = false
    @State private var newEntryPrefillClient: Client? = nil

    var body: some View {
        List {
            if filteredClients.isEmpty {
                Text("No clients yet.")
                    .foregroundStyle(.secondary)
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
                .onDelete(perform: deleteClients)
            }
        }
        .navigationTitle("Clients")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewClient = true
                } label: { Image(systemName: "person.crop.circle.badge.plus") }
                .accessibilityLabel("New Client")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewEntry = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("New Entry")
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
    }

    private var filteredClients: [Client] {
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return clients }
        return clients.filter { $0.name.localizedCaseInsensitiveContains(s) }
    }

    private func deleteClients(at offsets: IndexSet) {
        for index in offsets {
            ctx.delete(filteredClients[index])
        }
        try? ctx.save()
    }
}
