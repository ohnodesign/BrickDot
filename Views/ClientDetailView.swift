// Views/ClientDetailView.swift
import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme
    @Bindable var client: Client

    // Collapsible sections (To Do / In Progress start collapsed)
    @AppStorage("client.showDetails") private var showDetails = false
    @AppStorage("client.showStarred") private var showStarred = true
    @AppStorage("client.showTodo") private var showTodo = false
    @AppStorage("client.showInProgress") private var showInProgress = false
    @AppStorage("client.showAllClientDone") private var showAllClientDone = false
    @AppStorage("client.showDone") private var showDone = false
    @AppStorage("client.showStats") private var showStats = false
    @AppStorage("client.showInvoices") private var showInvoices = false
    @AppStorage("client.showRecent") private var showRecent = false
    @AppStorage("client.showTemplates") private var showTemplates = false
    @State private var showEdit       = false
    @State private var showNewEntry   = false
    @State private var showNewTemplate = false
    @State private var selectedTemplate: EntryTemplate? = nil
    @State private var showEntryPicker = false
    @State private var templateToEdit: EntryTemplate? = nil

    // Broad queries; filter in Swift
    @Query(sort: \Entry.serviceDate, order: .reverse) private var allEntries: [Entry]
    @Query(sort: \Invoice.createdAt,  order: .reverse) private var allInvoices: [Invoice]

    // Filtered for this client
    private var clientEntries: [Entry] { allEntries.filter { $0.client == client } }

    private var clientStarredSorted: [Entry] {
        clientEntries
            .filter { $0.isImportant && $0.status != .done }
            .sorted { $0.serviceDate > $1.serviceDate }
    }

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
        let all = allInvoices.flatMap { $0.entriesList }
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

            // Details (collapsed by default)
            Section {
                DisclosureGroup(isExpanded: $showDetails) {
                    EditableDetailRow(label: "Main Contact", text: $client.contactName)
                        .textInputAutocapitalization(.words)
                    EditableDetailRow(label: "Email", text: $client.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    EditableDetailRow(label: "Phone", text: $client.phone)
                        .keyboardType(.phonePad)
                    EditableDetailRow(label: "Business Phone", text: $client.businessPhone)
                        .keyboardType(.phonePad)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Address").font(.caption).foregroundStyle(.secondary)
                        TextField("Address", text: $client.address, axis: .vertical)
                            .lineLimit(2...4)
                            .onChange(of: client.address) { _, _ in try? ctx.save() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.text.rectangle")
                            .foregroundStyle(.accent)
                        Text("Details")
                    }
                }
            }

            // Starred
            Section {
                DisclosureGroup(isExpanded: $showStarred) {
                    let items = clientStarredSorted
                    if items.isEmpty {
                        Text("No starred items").foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { e in
                            NavigationLink { EditEntryView(entry: e) } label: {
                                SharedEntryRow(entry: e)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(e) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(e) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text("Starred (\(clientStarredSorted.count))")
                    }
                }
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(e) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(e) }
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(e) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(e) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        StatusDot(color: theme.running) // solid red in header replaced with theme.running
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingSwipe(e) }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) { leadingSwipe(e) }
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

            // Templates
            Section {
                DisclosureGroup(isExpanded: $showTemplates) {
                    if client.templatesList.isEmpty {
                        Text("No templates yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(client.templatesList.sorted { $0.name < $1.name }, id: \.persistentModelID) { template in
                            HStack {
                                Button {
                                    templateToEdit = template
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.name).font(.subheadline).fontWeight(.semibold)
                                        Text("\(template.service) — \(template.detail.isEmpty ? "No detail" : template.detail)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                Button {
                                    selectedTemplate = template
                                    showNewEntry = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    templateToEdit = template
                                } label: {
                                    Label("Edit", systemImage: "square.and.pencil")
                                }.tint(.blue)
                                Button(role: .destructive) {
                                    ctx.delete(template)
                                    try? ctx.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    Button {
                        showNewTemplate = true
                    } label: {
                        Label("New Template", systemImage: "plus.circle")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.accent)
                        Text("Templates (\(client.templatesList.count))")
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
                Menu {
                    Button {
                        selectedTemplate = nil
                        showNewEntry = true
                    } label: {
                        Label("Blank Entry", systemImage: "doc")
                    }
                    if !client.templatesList.isEmpty {
                        Divider()
                        ForEach(client.templatesList.sorted { $0.name < $1.name }, id: \.persistentModelID) { template in
                            Button {
                                selectedTemplate = template
                                showNewEntry = true
                            } label: {
                                Label(template.name, systemImage: "doc.text")
                            }
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.79, green: 0.25, blue: 0.25))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
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
            if let template = selectedTemplate {
                NavigationStack {
                    NewEntryView(
                        onSaved: { showNewEntry = false; selectedTemplate = nil },
                        prefillClient: client,
                        prefillTemplate: template
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                QuickAddView(
                    prefillClient: client,
                    onSaved: { showNewEntry = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showNewTemplate) {
            NavigationStack {
                NewTemplateView(client: client) {
                    showNewTemplate = false
                }
            }
        }
        .fullScreenCover(item: $templateToEdit) { template in
            NavigationStack {
                EntryTemplateEditorView(template: template)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { templateToEdit = nil }
                        }
                    }
            }
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
        let elapsed = e.runningElapsedHoursOrZero
        e.hours += elapsed
        e.timeLogsList.append(TimeLog(hours: elapsed, entry: e))
        e.timerStartedAt = nil
        try? ctx.save()
    }
    private func quickBump(_ e: Entry, _ h: Double) {
        e.hours += h
        e.timeLogsList.append(TimeLog(hours: h, entry: e))
        try? ctx.save()
    }
    private func markDone(_ e: Entry) {
        e.timerStartedAt = nil
        e.status = .done
        e.completedAt = Date()
        try? ctx.save()
    }

    @ViewBuilder
    func trailingSwipe(_ e: Entry) -> some View {
        if e.status == .inProgress && e.timerStartedAt != nil {
            Button { quickPauseAndAdd(e) } label: {
                Label("Pause & Add", systemImage: "pause.circle")
            }.tint(theme.dueToday)
        } else if e.status != .done {
            Button { quickStart(e) } label: {
                Label("Start", systemImage: "play.circle")
            }.tint(theme.success)
        }
        Button { quickBump(e, 0.25) } label: { Text("+15m") }.tint(theme.accent)
        Button { quickBump(e, 0.5) }  label: { Text("+30m") }.tint(theme.accentHover)
    }

    @ViewBuilder
    func leadingSwipe(_ e: Entry) -> some View {
        Button {
            e.isImportant.toggle()
            try? ctx.save()
        } label: {
            Label(e.isImportant ? "Unstar" : "Star",
                  systemImage: e.isImportant ? "star.slash.fill" : "star.fill")
        }.tint(.yellow)

        if e.status != .todo {
            Button { e.status = .todo; e.timerStartedAt = nil; try? ctx.save() } label: {
                Label("To Do", systemImage: "circle")
            }.tint(theme.dueToday)
        }
        if e.status != .inProgress {
            Button { e.status = .inProgress; if e.timerStartedAt == nil { e.timerStartedAt = Date() }; try? ctx.save() } label: {
                Label("In Progress", systemImage: "bolt.fill")
            }.tint(theme.running)
        }
        if e.status != .done {
            Button { markDone(e) } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
            }.tint(theme.success)
        }
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
    @Environment(\.appTheme) private var theme
    let pulsing: Bool
    @State private var animate = false
    var body: some View {
        Circle()
            .fill(theme.running)
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
    @Environment(\.appTheme) private var theme
    let status: EntryStatus
    let isImportant: Bool
    let pulsing: Bool   // only for in-progress when using dot

    private var color: Color {
        switch status {
        case .todo:       return theme.dueToday
        case .inProgress: return theme.running
        case .done:       return theme.success
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
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.detail.isEmpty ? entry.service : entry.detail)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
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
            Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct ClientInProgressRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: entry.timerStartedAt != nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.detail.isEmpty ? entry.service : entry.detail)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
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
            if entry.timerStartedAt != nil {
                Text(entry.runningElapsedHoursOrZero.hoursMinutesString)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.running.opacity(0.15)))
                    .foregroundStyle(theme.running)
            } else {
                Text(entry.serviceDate, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .onReceive(timer) { tick = $0 }
    }
}

private struct ClientDoneRow: View {
    let entry: Entry
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.detail.isEmpty ? entry.service : entry.detail)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
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
            if let completed = entry.completedAt {
                Text(completed, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RecentEntryRowWithInvoiceDot: View {
    let entry: Entry
    let isInvoiced: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusIconOrDot(status: entry.status, isImportant: entry.isImportant, pulsing: entry.status == .inProgress && entry.timerStartedAt != nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.detail.isEmpty ? entry.service : entry.detail)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if isInvoiced {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
                            .accessibilityLabel("Invoiced")
                    }
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
                Text(entry.hours * entry.rate,
                     format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    .font(.subheadline)
                if entry.hours > 0 {
                    Text("\(entry.hours, specifier: "%.1f")h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InvoiceRow: View {
    let invoice: Invoice
    private var totalAmount: Double {
        invoice.entriesList.reduce(0) { $0 + ($1.hours * $1.rate) }
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

private struct EditableDetailRow: View {
    let label: String
    @Binding var text: String
    @Environment(\.modelContext) private var ctx

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .onChange(of: text) { _, _ in try? ctx.save() }
        }
    }
}

// MARK: - Minimal inline editor
private struct ClientInlineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var client: Client
    var onClose: (Bool) -> Void   // pass true if saved

    @State private var name: String
    @State private var rate: Double
    @State private var colorIndex: Int
    @State private var shortcode: String
    @State private var contactName: String
    @State private var address: String
    @State private var phone: String
    @State private var businessPhone: String
    @State private var email: String

    init(client: Client, onClose: @escaping (Bool) -> Void) {
        self._client = Bindable(wrappedValue: client)
        self.onClose = onClose
        _name = State(initialValue: client.name)
        _rate = State(initialValue: client.rate)
        _colorIndex = State(initialValue: client.colorIndex)
        _shortcode = State(initialValue: client.shortcode)
        _contactName = State(initialValue: client.contactName)
        _address = State(initialValue: client.address)
        _phone = State(initialValue: client.phone)
        _businessPhone = State(initialValue: client.businessPhone)
        _email = State(initialValue: client.email)
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
            Section("Quick Add Shortcode") {
                TextField("e.g. cs, sve, dlw", text: $shortcode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Contact Details") {
                TextField("Main Contact Name", text: $contactName)
                    .textInputAutocapitalization(.words)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Business Phone", text: $businessPhone)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Color") {
                ClientColorPicker(selectedIndex: $colorIndex)
            }
            Section {
                Button {
                    client.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.rate = rate
                    client.colorIndex = colorIndex
                    client.shortcode = shortcode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    client.contactName = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.businessPhone = businessPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                    client.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
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

// MARK: - New Template View

private struct NewTemplateView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let client: Client
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var service: String = (Constants.services.first ?? "")
    @State private var detail: String = ""
    @State private var notes: String = ""
    @State private var defaultHours: Double = 0

    @State private var newSubtaskTitle: String = ""
    @State private var pendingSubtasks: [PendingTemplateSubtask] = []

    private struct PendingTemplateSubtask: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var isCompleted: Bool = false
        var order: Int = 0
    }

    var body: some View {
        Form {
            Section("Template Info") {
                TextField("Template Name", text: $name)
                Picker("Service", selection: $service) {
                    ForEach(Constants.services, id: \.self) { svc in
                        Text(svc).tag(svc)
                    }
                }
            }

            Section("Default Values") {
                TextField("Detail / Description", text: $detail)
                HStack {
                    Text("Default Hours")
                    Spacer()
                    TextField("0.00", value: $defaultHours, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }

            Section("Notes") {
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Default notes for entries created from this template…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }

            // Subtasks editor - no nested List, just ForEach
            Section {
                if pendingSubtasks.isEmpty {
                    Text("No subtasks yet").foregroundStyle(.secondary)
                } else {
                    ForEach($pendingSubtasks) { $st in
                        HStack {
                            Button(action: { st.isCompleted.toggle() }) {
                                Image(systemName: st.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(st.isCompleted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)

                            TextField("Subtask title", text: $st.title)

                            Spacer()

                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        withAnimation {
                            pendingSubtasks.remove(atOffsets: offsets)
                            normalizeOrders()
                        }
                    }
                    .onMove { source, dest in
                        withAnimation {
                            pendingSubtasks.move(fromOffsets: source, toOffset: dest)
                            normalizeOrders()
                        }
                    }
                }

                HStack {
                    TextField("New subtask", text: $newSubtaskTitle)
                        .onSubmit(addPendingSubtask)
                    Button(action: addPendingSubtask) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Subtasks")
                    Spacer()
                    if !pendingSubtasks.isEmpty {
                        Text("\(pendingSubtasks.count)").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    saveTemplate()
                } label: {
                    Label("Save Template", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("New Template")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
    }

    private func addPendingSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation {
            let order = (pendingSubtasks.map { $0.order }.max() ?? -1) + 1
            pendingSubtasks.append(PendingTemplateSubtask(title: title, isCompleted: false, order: order))
            newSubtaskTitle = ""
        }
    }

    private func normalizeOrders() {
        for idx in pendingSubtasks.indices {
            if pendingSubtasks[idx].order != idx { pendingSubtasks[idx].order = idx }
        }
    }

    private func saveTemplate() {
        let template = EntryTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            service: service,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultHours: defaultHours,
            client: client
        )
        ctx.insert(template)

        // Attach any pending subtasks to the template
        if !pendingSubtasks.isEmpty {
            let sorted = pendingSubtasks.sorted { $0.order < $1.order }
            for st in sorted where !st.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let sub = TemplateSubtask(title: st.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                          isCompleted: st.isCompleted,
                                          order: st.order,
                                          template: template)
                template.subtasksList.append(sub)
            }
        }

        try? ctx.save()
        onSaved()
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

