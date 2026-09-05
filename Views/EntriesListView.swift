import SwiftUI
import SwiftData

struct EntriesListView: View, Identifiable {
    let id = UUID()
    let title: String
    let entries: [Entry]

    @State private var showAll: Bool = false
    private var displayedEntries: [Entry] {
        showAll ? entries : Array(entries.prefix(20))
    }
    private var totalHours: Double { entries.reduce(0.0) { $0 + $1.hours } }
    private var totalAmount: Double { entries.reduce(0.0) { $0 + ($1.hours * $1.rate) } }

    @Environment(\.modelContext) private var ctx
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntriesStored: [Entry]
    /// Filtered in Swift, not in the `@Query` predicate. A predicate here
    /// wedges the app — see the note on `Entry.workOnly(_:)`.
    private var allEntries: [Entry] { Entry.workOnly(allEntriesStored) }

    var body: some View {
        NavigationStack {
            List(displayedEntries) { entry in
                if title == "Logged Today" {
                    NavigationLink { EditEntryView(entry: entry) } label: {
                        LoggedTodayEntryRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.25
                                e.timeLogsList.append(TimeLog(hours: 0.25, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+15m") }.tint(.blue)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.5
                                e.timeLogsList.append(TimeLog(hours: 0.5, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+30m") }.tint(.indigo)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 1.0
                                e.timeLogsList.append(TimeLog(hours: 1.0, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+1h") }.tint(.purple)

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.timerStartedAt = nil
                                e.status = .done
                                e.completedAt = Date()
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: {
                            Label("Done", systemImage: "checkmark.circle")
                        }

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let doomed = allEntries[idx]
                                ctx.delete(doomed)
                                try? ctx.save()
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                } else {
                    NavigationLink { EditEntryView(entry: entry) } label: {
                        SharedEntryRow(entry: entry)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.25
                                e.timeLogsList.append(TimeLog(hours: 0.25, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+15m") }.tint(.blue)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.5
                                e.timeLogsList.append(TimeLog(hours: 0.5, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+30m") }.tint(.indigo)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 1.0
                                e.timeLogsList.append(TimeLog(hours: 1.0, entry: e))
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: { Text("+1h") }.tint(.purple)

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.timerStartedAt = nil
                                e.status = .done
                                e.completedAt = Date()
                                e.markModified()
                                try? ctx.save()
                            }
                        } label: {
                            Label("Done", systemImage: "checkmark.circle")
                        }

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let doomed = allEntries[idx]
                                ctx.delete(doomed)
                                try? ctx.save()
                            }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            
            // Footer: Show more + Totals
            if entries.count > 20 {
                Button(action: { withAnimation { showAll.toggle() } }) {
                    HStack {
                        Spacer()
                        Label(showAll ? "Show Less" : "Show All (\(entries.count))", systemImage: showAll ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
            }

            // Totals (styled card)
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Items"); Spacer(); Text("\(entries.count)").fontWeight(.semibold) }
                    HStack { Text("Hours"); Spacer(); Text(totalHours, format: .number.precision(.fractionLength(2))).fontWeight(.semibold) }
                    HStack {
                        Text("Amount"); Spacer()
                        Text(totalAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.08))
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 12, trailing: 12))
            
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

private struct LoggedTodayEntryRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    private var todayHours: Double {
        entry.timeLogsList.filter { Calendar.current.isDateInToday($0.addedAt) }
            .reduce(0.0) { $0 + $1.hours }
    }

    var body: some View {
        HStack(spacing: 10) {
            SharedStatusMark(
                color: statusColor(entry.status),
                isImportant: entry.isImportant,
                pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if entry.service == "COMM", let icon = commChannelIcon(for: entry.commChannel) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(entry.service.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(theme.accent)
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.clientName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                let amount = todayHours * entry.rate
                Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
                Text("Today: \(todayHours, specifier: "%.1f")h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
