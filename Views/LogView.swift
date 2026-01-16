import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]

    @State private var searchText: String = ""
    @State private var statusFilter: EntryStatus? = nil   // nil = All
    @State private var showNewEntry = false

    var body: some View {
        NavigationStack {
            List {
                // Filter controls
                Section("Filter") {
                    StatusFilterBar(selection: $statusFilter)
                }

                // Entries
                Section("Entries") {
                    let entries = filteredEntries
                    if entries.isEmpty {
                        Text("No entries").foregroundStyle(.secondary)
                    } else {
                        ForEach(entries, id: \.persistentModelID) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                LogEntryRow(entry: e)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    ctx.delete(e); try? ctx.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Log")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewEntry = true } label: {
                        Image(systemName: "plus.circle")
                            .imageScale(.large)
                            .accessibilityLabel("New Entry")
                    }
                }
            }
            .sheet(isPresented: $showNewEntry) {
                NavigationStack {
                    NewEntryView(onSaved: { showNewEntry = false })
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Derived (important-first + filters)

    private var filteredEntries: [Entry] {
        var result = allEntries

        if let f = statusFilter {
            result = result.filter { $0.status == f }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter { e in
                let clientName = e.client.name.lowercased()
                let service = e.service.lowercased()
                let detail = e.detail.lowercased()
                return clientName.contains(q) || service.contains(q) || detail.contains(q)
            }
        }

        // ⭐️ important-first, then newest first
        result.sort {
            if $0.isImportant != $1.isImportant {
                return $0.isImportant && !$1.isImportant
            }
            let d0 = $0.completedAt ?? $0.serviceDate
            let d1 = $1.completedAt ?? $1.serviceDate
            return d0 > d1
        }

        return result
    }
}

// MARK: - Row

private struct LogEntryRow: View {
    let entry: Entry

    private func color(for status: EntryStatus) -> Color {
        switch status {
        case .todo:       return .orange
        case .inProgress: return .brick
        case .done:       return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // ⭐️ or colored dot before client name (same color as status)
                StatusMark(color: color(for: entry.status), starred: entry.isImportant)

                Text(entry.client.name).font(.headline)
                Spacer()
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
            }

            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(entry.service)
                Text("•")
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                Spacer()
                Text("\(entry.hours, specifier: "%.2f")h")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Status mark (star-or-dot)

private struct StatusMark: View {
    let color: Color
    let starred: Bool

    var body: some View {
        Group {
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold)) // slightly larger star
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Status filter bar (chips with dots)

private struct StatusFilterBar: View {
    @Binding var selection: EntryStatus?

    private struct Chip: Identifiable {
        let id = UUID()
        let label: String
        let color: Color?   // nil for "All"
        let value: EntryStatus?
    }

    private var chips: [Chip] {
        [
            Chip(label: "All",         color: nil,       value: nil),
            Chip(label: "To Do",       color: .orange,   value: .todo),
            Chip(label: "In Progress", color: .brick,    value: .inProgress),
            Chip(label: "Done",        color: .green,    value: .done)
        ]
    }

    var body: some View {
        // natural-size chips, single line labels (no wrapping)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let isSelected = (selection == chip.value)
                    Button {
                        selection = chip.value
                    } label: {
                        HStack(spacing: 6) {
                            if let color = chip.color {
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                            }
                            Text(chip.label)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected
                                      ? Color.secondary.opacity(0.15)
                                      : Color.secondary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }
}
