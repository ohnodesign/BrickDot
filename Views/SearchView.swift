import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Client.name) private var allClients: [Client]

    @State private var searchText = ""
    @AppStorage("search.recents") private var recentsData: Data = Data()

    private var recents: [String] {
        (try? JSONDecoder().decode([String].self, from: recentsData)) ?? []
    }

    private func saveRecent(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recents.filter { $0.lowercased() != trimmed.lowercased() }
        list.insert(trimmed, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentsData = (try? JSONEncoder().encode(list)) ?? Data()
    }

    private func clearRecents() {
        recentsData = (try? JSONEncoder().encode([String]())) ?? Data()
    }

    private var results: [Entry] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return allEntries.filter { e in
            e.clientName.lowercased().contains(q)
            || e.service.lowercased().contains(q)
            || e.detail.lowercased().contains(q)
            || e.notes.lowercased().contains(q)
        }
    }

    private var clientResults: [Client] {
        guard !searchText.isEmpty else { return [] }
        let q = searchText.lowercased()
        return allClients.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    // Recents
                    if !recents.isEmpty {
                        Section {
                            ForEach(recents, id: \.self) { term in
                                Button {
                                    searchText = term
                                } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        Text(term)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            HStack {
                                Text("Recents")
                                Spacer()
                                Button("Clear") { clearRecents() }
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    // Client matches
                    if !clientResults.isEmpty {
                        Section("Clients") {
                            ForEach(clientResults, id: \.persistentModelID) { client in
                                NavigationLink {
                                    ClientDetailView(client: client)
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(client.accentColor)
                                            .frame(width: 10, height: 10)
                                        Text(client.name)
                                    }
                                }
                            }
                        }
                    }

                    // Entry matches
                    Section("Entries (\(results.count))") {
                        if results.isEmpty {
                            Text("No results").foregroundStyle(.secondary)
                        } else {
                            ForEach(results.prefix(50)) { entry in
                                NavigationLink {
                                    EditEntryView(entry: entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(entry.client?.accentColor ?? ClientColors.palette[0].color)
                                                .frame(width: 8, height: 8)
                                            Text(entry.displayClientName)
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(entry.status.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !entry.detail.isEmpty {
                                            Text(entry.detail)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        HStack {
                                            Text(entry.service)
                                                .font(.caption2)
                                            Text("·")
                                            Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                                                .font(.caption2)
                                        }
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) {
                saveRecent(searchText)
            }
            .onChange(of: searchText) { old, new in
                // Save to recents when user clears or changes away from a meaningful search
                if !old.isEmpty && old.count >= 3 && (new.isEmpty || new.count < old.count - 2) {
                    saveRecent(old)
                }
            }
            .onDisappear {
                if searchText.count >= 3 {
                    saveRecent(searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

