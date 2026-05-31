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
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]

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
                                try? ctx.save()
                            }
                        } label: { Text("+15m") }.tint(.blue)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.5
                                e.timeLogsList.append(TimeLog(hours: 0.5, entry: e))
                                try? ctx.save()
                            }
                        } label: { Text("+30m") }.tint(.indigo)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 1.0
                                e.timeLogsList.append(TimeLog(hours: 1.0, entry: e))
                                try? ctx.save()
                            }
                        } label: { Text("+1h") }.tint(.purple)

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.timerStartedAt = nil
                                e.status = .done
                                e.completedAt = Date()
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
                                try? ctx.save()
                            }
                        } label: { Text("+15m") }.tint(.blue)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 0.5
                                e.timeLogsList.append(TimeLog(hours: 0.5, entry: e))
                                try? ctx.save()
                            }
                        } label: { Text("+30m") }.tint(.indigo)

                        Button {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.hours += 1.0
                                e.timeLogsList.append(TimeLog(hours: 1.0, entry: e))
                                try? ctx.save()
                            }
                        } label: { Text("+1h") }.tint(.purple)

                        Button(role: .destructive) {
                            if let idx = allEntries.firstIndex(where: { $0.persistentModelID == entry.persistentModelID }) {
                                let e = allEntries[idx]
                                e.timerStartedAt = nil
                                e.status = .done
                                e.completedAt = Date()
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
        }
    }
}

private struct LoggedTodayEntryRow: View {
    let entry: Entry

    private var todayHours: Double {
        entry.timeLogsList.filter { Calendar.current.isDateInToday($0.addedAt) }
            .reduce(0.0) { $0 + $1.hours }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SharedStatusMark(
                    color: entry.status.color,
                    isImportant: entry.isImportant,
                    pulsing: entry.status == .inProgress && entry.timerStartedAt != nil
                )
                Text(entry.clientName).font(.headline)
                Spacer()
                let amount = todayHours * entry.rate
                Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(entry.service); Text("•")
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                Spacer()
                Text("Today: \(todayHours, specifier: "%.2f")h")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
