// Views/ClientDetailView.swift
import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var client: Client

    // Collapsible sections (To Do / In Progress start collapsed)
    @AppStorage("client.showTodo") private var showTodo = false
    @AppStorage("client.showInProgress") private var showInProgress = false
    @AppStorage("client.showAllClientDone") private var showAllClientDone = false
    @AppStorage("client.showDone") private var showDone = false
    @AppStorage("client.showStats") private var showStats = false
    @AppStorage("client.showInvoices") private var showInvoices = false
    @AppStorage("client.showRecent") private var showRecent = false
    @State private var showEdit       = false
    @State private var showNewEntry   = false

    // Broad queries; filter in Swift
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Invoice.createdAt,  order: .reverse) private var allInvoices: [Invoice]

    // Filtered for this client
    private var clientEntries: [Entry] { allEntries.filter { $0.client == client } }

    // Important-first sorting, then newest first
    private var clientTodosSorted: [Entry] {
        clientEntries
            .filter { $0.status == .todo }
            .sorted {
                if $0.isImportant != $1.isImportant { return $0.isImportant && !$1.isImportant }
                return $0.serviceDate > $1.serviceDate
            }
    }
    private var clientInProgressSorted: [Entry] {
        clientEntries
            .filter { $0.status == .inProgress }
            .sorted {
                if $0.isImportant != $1.isImportant { return $0.isImportant && !$1.isImportant }
                return $0.serviceDate > $1.serviceDate
            }
    }

    private var clientDoneSorted: [Entry] {
        clientEntries
            .filter { $0.status == .done }
            .sorted {
                let d0 = $0.completedAt ?? $0.serviceDate
                let d1 = $1.completedAt ?? $1.serviceDate
                return d0 > d1
            }
    }

    private var clientTodayDone: [Entry] {
        clientEntries.filter {
            $0.status == .done && Calendar.current.isDateInToday(($0.completedAt ?? $0.serviceDate))
        }
    }

    private var clientThisWeekDone: [Entry] {
        let now = Date()
        let start = now.bdStartOfWeek
        let end   = now.bdEndOfWeek
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= start && d <= end
        }
    }

    private var clientLastWeekDone: [Entry] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .weekOfYear, value: -1, to: Date())?.bdStartOfWeek,
              let end = cal.date(byAdding: .weekOfYear, value: -1, to: Date())?.bdEndOfWeek else { return [] }
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= start && d <= end
        }
    }

    private var clientThisMonthDone: [Entry] {
        let now = Date()
        let start = now.startOfMonth
        let end   = now.endOfMonth
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= start && d <= end
        }
    }

    private var clientLastMonthDone: [Entry] {
        let cal = Calendar.current
        guard let prevMonth = cal.date(byAdding: .month, value: -1, to: Date()) else { return [] }
        let start = prevMonth.startOfMonth
        let end   = prevMonth.endOfMonth
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= start && d <= end
        }
    }

    private var clientThisQuarterDone: [Entry] {
        let now = Date()
        let q = now.bdQuarterBounds
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= q.start && d <= q.end
        }
    }

    private var clientYTDone: [Entry] {
        let cal = Calendar.current
        let now = Date()
        let startOfYear = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        return clientEntries.filter { e in
            let d = (e.completedAt ?? e.serviceDate)
            return e.status == .done && d >= startOfYear && d <= now
        }
    }

    private var clientInvoices: [Invoice] { allInvoices.filter { $0.client == client } }
    private var clientInvoicesSorted: [Invoice] { clientInvoices.sorted { $0.createdAt > $1.createdAt } }

    // Fast lookup set of invoiced Entry IDs (for green dot in Recent)
    private var invoicedEntryIDs: Set<PersistentIdentifier> {
        let all = allInvoices.flatMap { $0.entries }
        return Set(all.map { $0.persistentModelID })
    }

    var body: some View {
        List {
            // Client summary
            Section("Client") {
                HStack { Text("Name"); Spacer(); Text(client.name).foregroundStyle(.secondary) }
                HStack {
                    Text("Default Rate"); Spacer()
                    Text(client.rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .foregroundStyle(.secondary)
                }
                HStack { Text("Entries"); Spacer(); Text("\(clientEntries.count)").foregroundStyle(.secondary) }
                HStack { Text("Invoices"); Spacer(); Text("\(clientInvoices.count)").foregroundStyle(.secondary) }
            }

            // To Do - matches HomeView (star/dot before client, important-first)
            Section {
                DisclosureGroup(isExpanded: $showTodo) {
                    let items = clientTodosSorted
                    if items.isEmpty {
                        Text("No to-do items").foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    } else {
                        ForEach(items, id: \.persistentModelID) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                ClientTodoRow(entry: e)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(color: .orange)
                        Text("To Do (\(clientTodosSorted.count))")
                    }
                }
            }

            // In Progress - matches HomeView + swipe actions, important-first
            Section {
                DisclosureGroup(isExpanded: $showInProgress) {
                    let active = clientInProgressSorted
                    if active.isEmpty {
                        Text("No in-progress items").foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    } else {
                        ForEach(active, id: \.persistentModelID) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                ClientInProgressRow(entry: e)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if e.timerStartedAt != nil {
                                    Button { quickPauseAndAdd(e) } label: {
                                        Label("Pause & Add", systemImage: "pause.circle")
                                    }.tint(.orange)
                                } else {
                                    Button { quickStart(e) } label: {
                                        Label("Start", systemImage: "play.circle")
                                    }.tint(.green)
                                }
                                Button { quickBump(e, 0.25) } label: { Text("+15m") }.tint(.blue)
                                Button { quickBump(e, 0.5) }  label: { Text("+30m") }.tint(.indigo)
                                Button { quickBump(e, 1.0) }  label: { Text("+1h") }.tint(.purple)
                                Button(role: .destructive) { markDone(e) } label: {
                                    Label("Done", systemImage: "checkmark.circle")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(color: .brick) // solid red in header
                        Text("In Progress (\(clientInProgressSorted.count))")
                    }
                }
            }

            // Done - last 20, sorted by completion date (fallback to service date)
            Section {
                DisclosureGroup(isExpanded: $showDone) {
                    let items = clientDoneSorted
                    let displayed = showAllClientDone ? items : Array(items.prefix(20))
                    if items.isEmpty {
                        Text("No done items").foregroundStyle(.secondary)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    } else {
                        ForEach(displayed, id: \.persistentModelID) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                ClientDoneRow(entry: e)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        }
                        if items.count > 20 {
                            Button(action: { withAnimation { showAllClientDone.toggle() } }) {
                                HStack {
                                    Spacer()
                                    Text(showAllClientDone ? "Show Less" : "Show All (\(items.count))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(color: .green)
                        Text("Done (\(clientDoneSorted.count))")
                    }
                }
            }

            // Stats (completed-only)
            Section {
                DisclosureGroup(isExpanded: $showStats) {
                    ClientStatsCard(
                        today: clientTodayDone,
                        week: clientThisWeekDone,
                        lastWeek: clientLastWeekDone,
                        month: clientThisMonthDone,
                        lastMonth: clientLastMonthDone,
                        quarter: clientThisQuarterDone,
                        yearToDate: clientYTDone
                    )
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.accent)
                        Text("Stats")
                    }
                }
            }

            // Invoices (collapsed by default)
            Section {
                DisclosureGroup(isExpanded: $showInvoices) {
                    if clientInvoicesSorted.isEmpty {
                        Text("No invoices yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(clientInvoicesSorted, id: \.persistentModelID) { inv in
                            NavigationLink { InvoiceDetailView(invoice: inv) } label: {
                                InvoiceRow(invoice: inv)
                            }
                        }
                    }
                } label: { Text("Invoices (\(clientInvoices.count))") }
            }

            // Recent entries - status icon (star/dot) + keep green invoiced dot
            Section {
                DisclosureGroup(isExpanded: $showRecent) {
                    if clientEntries.isEmpty {
                        Text("No entries yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(clientEntries.prefix(20), id: \.persistentModelID) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                RecentEntryRowWithInvoiceDot(
                                    entry: e,
                                    isInvoiced: invoicedEntryIDs.contains(e.persistentModelID)
                                )
                            }
                        }
                    }
                } label: { Text("Recent Entries (\(min(clientEntries.count, 20)))") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(client.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewEntry = true } label: {
                    Image(systemName: "plus.circle")
                        .imageScale(.large)
                        .accessibilityLabel("New Entry")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEdit = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("Edit Client")
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                ClientInlineEditor(client: client) { didSave in
                    if didSave { try? ctx.save() }
                    showEdit = false
                }
            }
        }
        .sheet(isPresented: $showNewEntry) {
            NavigationStack {
                NewEntryView(onSaved: { showNewEntry = false }, prefillClient: client)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Quick actions (same as HomeView)
    private func quickStart(_ e: Entry) {
        e.status = .inProgress
        if e.timerStartedAt == nil { e.timerStartedAt = Date() }
        try? ctx.save()
    }
    private func quickPauseAndAdd(_ e: Entry) {
        guard e.timerStartedAt != nil else { return }
        e.hours += e.runningElapsedHoursOrZero
        e.timeLogs.append(TimeLog(hours: e.runningElapsedHoursOrZero, entry: e))
        e.timerStartedAt = nil
        try? ctx.save()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogs.append(TimeLog(hours: h, entry: e))
        try? ctx.save()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        try? ctx.save()
    }
}

// MARK: - Rows & Small Views (mirrors HomeView)

// Simple non-pulsing dot
private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// Pulsing red dot used in In Progress rows
private struct BrickDot: View {
    let pulsing: Bool
    @State private var animate = false
    var body: some View {
        Circle()
            .fill(Color.brick)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing && animate ? 1.35 : 1.0)
            .opacity(pulsing && animate ? 0.45 : 1.0)
            .onAppear { startIfNeeded() }
            .onChange(of: pulsing) { _, _ in startIfNeeded() }
    }
    private func startIfNeeded() {
        animate = false
        if pulsing {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

/// Star-or-dot in the correct color, like HomeView (slightly larger star).
private struct StatusIconOrDot: View {
    let status: EntryStatus
    let isImportant: Bool
    let pulsing: Bool   // only for in-progress when using dot

    private var color: Color {
        switch status {
        case .todo:       return .orange
        case .inProgress: return .brick
        case .done:       return .green
        }
    }

    var body: some View {
        if isImportant {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        } else {
            if status == .inProgress {
                BrickDot(pulsing: pulsing)
            } else {
                StatusDot(color: color)
            }
        }
    }
}

// To Do row (star/dot before client)
private struct ClientTodoRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: false)
                Text(entry.client.name)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(entry.service)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(entry.detail.isEmpty ? "No description" : entry.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// In-Progress row (star or pulsing red dot)
private struct ClientInProgressRow: View {
    let entry: Entry
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: entry.timerStartedAt != nil)
                Text(entry.client.name)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if entry.timerStartedAt != nil && !entry.isImportant {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(entry.runningElapsedHoursOrZero.hoursMinutesString).monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Text(entry.service)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .onReceive(timer) { now in _ = now; tick = now }
    }
}

// Done row (star/dot before client like others)
private struct ClientDoneRow: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: false)
                Text(entry.client.name)
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(entry.service)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// Recent entry row - status star/dot + keep green invoiced dot
private struct RecentEntryRowWithInvoiceDot: View {
    let entry: Entry
    let isInvoiced: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: entry.status == .inProgress && entry.timerStartedAt != nil)

                Text(entry.client.name).font(.headline)

                // Invoiced indicator stays (small green dot)
                if isInvoiced {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Invoiced")
                }

                Spacer()
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.subheadline)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(entry.service); Text("•")
                Text(entry.serviceDate, format: .dateTime.year().month().day())
                Spacer()
                Text("\(entry.hours, specifier: "%.2f")h")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    private var totalAmount: Double {
        invoice.entries.reduce(0) { $0 + ($1.hours * $1.rate) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(invoice.title).font(.headline).lineLimit(1)
                Spacer()
                if let n = invoice.number, !n.isEmpty {
                    Text("#\(n)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(invoice.createdAt, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
            }
            .font(.caption)
        }
    }
}

// MARK: - Minimal inline editor (unchanged)
private struct ClientInlineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var client: Client
    var onClose: (Bool) -> Void   // pass true if saved

    @State private var name: String
    @State private var rate: Double

    init(client: Client, onClose: @escaping (Bool) -> Void) {
        self._client = Bindable(wrappedValue: client)
        self.onClose = onClose
        _name = State(initialValue: client.name)
        _rate = State(initialValue: client.rate)
    }

    var body: some View {
        Form {
            Section("Edit Client") {
                TextField("Name", text: $name)
                HStack {
                    Text("Rate"); Spacer()
                    TextField("Rate", value: $rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }
            }
            Section {
                Button {
                    client.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.rate = rate
                    onClose(true)
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down.fill")
                }
                Button(role: .cancel) { onClose(false) } label: {
                    Text("Cancel")
                }
            }
        }
        .navigationTitle("Edit Client")
    }
}

// MARK: - Client Stats (completed-only)

private struct ClientStatsCard: View {
    let today: [Entry]
    let week: [Entry]
    let lastWeek: [Entry]
    let month: [Entry]
    let lastMonth: [Entry]
    let quarter: [Entry]
    let yearToDate: [Entry]

    private var cols: [GridItem] { [GridItem(.flexible()), GridItem(.flexible())] }

    var body: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            SharedStatPill(title: "Today", entries: today, icon: "sun.max.fill")
            SharedStatPill(title: "This Week", entries: week, icon: "calendar")
            SharedStatPill(title: "Last Week", entries: lastWeek, icon: "calendar")
            SharedStatPill(title: "This Month", entries: month, icon: "calendar.badge.clock")
            SharedStatPill(title: "Last Month", entries: lastMonth, icon: "calendar.badge.clock")
            SharedStatPill(title: "This Quarter", entries: quarter, icon: "calendar.badge.exclamationmark")
            SharedStatPill(title: "Year to Date", entries: yearToDate, icon: "calendar.badge.plus")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date helpers (scoped)

private extension Date {
    var bdEndOfDay: Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: self)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? self
    }
}

