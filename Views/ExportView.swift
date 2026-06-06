// Views/ExportView.swift
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

// Local month helper to avoid target membership issues
extension Calendar {
    /// Returns an array of month anchor dates between the two dates (inclusive).
    /// Each returned date is normalized to the first day of its month using this calendar.
    func monthsBetween(start: Date, end: Date) -> [Date] {
        let cal = self
        let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: min(start, end))) ?? min(start, end)
        let endMonth   = cal.date(from: cal.dateComponents([.year, .month], from: max(start, end))) ?? max(start, end)
        var months: [Date] = []
        var current = startMonth
        while current <= endMonth {
            months.append(current)
            guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return months
    }
}

// MARK: - Enums local to Export UI (no conflicts with Settings)

enum ExportMode: String, CaseIterable {
    case singleMonth = "Month"
    case multiMonth  = "Months"
    case dateRange   = "Range"
}

// MARK: - Identifiable share payload

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - Small view used for service chips

private struct ServiceToggle: View {
    let title: String
    let isOn: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if isOn { Image(systemName: "checkmark.circle.fill") }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View

struct ExportView: View {
    @Environment(\.modelContext) private var ctx

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Entry.serviceDate) private var allEntries: [Entry]
    @Query(sort: \Invoice.createdAt) private var allInvoices: [Invoice]

    @State private var selectedClient: Client?
    @State private var mode: ExportMode = .singleMonth

    @State private var monthStart: Date = Date()
    @State private var monthEnd: Date = Date()
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()

    // Added states for backup feedback alert
    @State private var backupFeedbackMessage: String? = nil
    @State private var showBackupFeedback: Bool = false

    // ✅ Read/write user prefs (aligned with SettingsView keys/values)
    @AppStorage("export.useQuickBooksHeaders") private var useQuickBooksHeaders = false
    @AppStorage("export.includeNotes")         private var includeNotes = false
    @AppStorage("export.includeSubtasks")      private var includeSubtasks = false
    @AppStorage("agenda.defaultScope")         private var agendaScopeRaw: String  = "selectedClient" // "selectedClient" | "allClients"
    @AppStorage("agenda.defaultFormat")        private var agendaFormatRaw: String = "plain"          // "plain" | "markdown"
    @AppStorage("backup.folder.bookmark")      private var backupFolderBookmark: Data?
    @AppStorage("backup.lastRun")              private var lastBackupDate: Double = 0

    @State private var resolvedBackupFolderURL: URL? = nil

    @State private var sharePayload: SharePayload?

    @State private var selectedServices = Set<String>()
    @State private var showServices = true

    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var importInfo: String?
    @State private var showImportInfo = false

    @State private var showFolderPicker = false
    @State private var backupObserver: NSObjectProtocol? = nil


    private var headers: ExportHeaders { useQuickBooksHeaders ? .quickBooks : ExportHeaders() }

    private var invoicedEntryIDs: Set<PersistentIdentifier> {
        let all = allInvoices.flatMap { $0.entriesList }
        return Set(all.map { $0.persistentModelID })
    }

    private var lastBackupDisplay: String {
        let any = UserDefaults.standard.object(forKey: "backup.lastRun")
        let date: Date
        if let d = any as? Date { date = d }
        else if let t = any as? Double { date = Date(timeIntervalSince1970: t) }
        else { return "—" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    var body: some View {
        NavigationStack {
            Form {
                // CSV Export
                Section {
                    Toggle("Use QuickBooks-style headers", isOn: $useQuickBooksHeaders)
                    Button {
                        switch mode {
                        case .singleMonth: exportSingleMonth()
                        case .multiMonth:  exportMultiMonth()
                        case .dateRange:   exportRange()
                        }
                    } label: {
                        Label(useQuickBooksHeaders ? "Export for QuickBooks (CSV)" : "Export CSV",
                              systemImage: "square.and.arrow.up")
                    }
                    .disabled(currentEntries.isEmpty || selectedClient == nil)
                }

                // Client
                Section {
                    Picker("Client", selection: $selectedClient) {
                        ForEach(clients, id: \.persistentModelID) { c in
                            Text(c.name).tag(Optional(c))
                        }
                    }
                }

                // Agenda Export
                Section {
                    Picker("Scope", selection: $agendaScopeRaw) {
                        Text("Selected Client").tag("selectedClient")
                        Text("All Clients").tag("allClients")
                    }
                    Picker("Format", selection: $agendaFormatRaw) {
                        Text("Plain Text").tag("plain")
                        Text("Markdown").tag("markdown")
                    }

                    Toggle("Include completed subtasks", isOn: $includeSubtasks)

                    Button {
                        exportAgenda()
                    } label: {
                        Label("Export Agenda", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .disabled({
                        agendaScopeRaw == "selectedClient" && selectedClient == nil
                    }())

                    Button {
                        copyAgendaToClipboard()
                    } label: {
                        Label("Copy Agenda", systemImage: "doc.on.clipboard")
                    }
                    .disabled({
                        agendaScopeRaw == "selectedClient" && selectedClient == nil
                    }())
                } header: {
                    Text("Agenda Export")
                } footer: {
                    Text("Includes To Do, In Progress, and the last 20 Done items (Done respects the service filter).")
                }

                // Service Filter
                Section {
                    DisclosureGroup(isExpanded: $showServices) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(Constants.services, id: \.self) { svc in
                                ServiceToggle(title: svc, isOn: selectedServices.contains(svc)) {
                                    if selectedServices.contains(svc) { selectedServices.remove(svc) }
                                    else { selectedServices.insert(svc) }
                                }
                            }
                        }
                        if !selectedServices.isEmpty {
                            Button("Clear Service Filter") { selectedServices.removeAll() }
                                .foregroundStyle(.secondary).padding(.top, 6)
                        }
                    } label: {
                        HStack {
                            Text("Filter by Service")
                            if !selectedServices.isEmpty {
                                Spacer()
                                Text("\(selectedServices.count) selected")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Mode + Dates
                Section {
                    Picker("Export", selection: $mode) {
                        ForEach(ExportMode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .singleMonth:
                        DatePicker("Month", selection: $monthStart, displayedComponents: .date)
                    case .multiMonth:
                        DatePicker("From", selection: $monthStart, displayedComponents: .date)
                        DatePicker("To", selection: $monthEnd, displayedComponents: .date)
                    case .dateRange:
                        DatePicker("Start", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("End", selection: $rangeEnd, displayedComponents: .date)
                    }
                }

                // Stats
                Section("Stats") {
                    let entries = currentEntries
                    if entries.isEmpty {
                        Text("No entries in selection.").foregroundStyle(.secondary)
                    } else {
                        let totalHours = entries.reduce(0.0) { $0 + $1.hours }
                        let totalAmount = entries.reduce(0.0) { $0 + ($1.hours * $1.rate) }
                        HStack { Text("Items");  Spacer(); Text("\(entries.count)") }
                        HStack { Text("Hours");  Spacer(); Text(totalHours, format: .number.precision(.fractionLength(2))) }
                        HStack {
                            Text("Amount"); Spacer()
                            Text(totalAmount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        }
                    }
                }

                // Preview (excludes Done)
                previewSection(entries: currentEntries)

                // Backup / Restore
                Section("Backup / Restore") {
                    Button {
                        if let url = try? Backup.exportJSON(ctx: ctx) {
                            sharePayload = SharePayload(items: [url])
                        }
                    } label: {
                        Label("Export Backup (JSON)", systemImage: "arrow.up.doc")
                    }

                    Button {
                        DispatchQueue.main.async { showImportPicker = true }
                    } label: {
                        Label("Import Backup (JSON)", systemImage: "arrow.down.doc")
                    }
                    
                    HStack {
                        Text("Last Auto-Backup")
                        Spacer()
                        Text(lastBackupDisplay).foregroundStyle(.secondary)
                    }
                    Button {
                        AutoBackup.perform(ctx: ctx)
                    } label: {
                        Label("Back Up Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    // Added status line indicating chosen folder
                    HStack {
                        Text("Chosen Folder")
                        Spacer()
                        Text(resolvedBackupFolderURL?.lastPathComponent ?? "None").foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    Button {
                        pickBackupFolder()
                    } label: {
                        Label("Choose Backup Folder…", systemImage: "folder.badge.plus")
                    }
                    
                    if let folder = resolvedBackupFolderURL {
                        HStack {
                            Image(systemName: "folder")
                            Text(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)
                            Spacer()
                            Button("Clear") {
                                backupFolderBookmark = nil
                                resolvedBackupFolderURL = nil
                            }
                            .buttonStyle(.borderless)
                        }
                        Button {
                            writeTestBackupToChosenFolder()
                        } label: {
                            Label("Save Test Backup to Chosen Folder", systemImage: "tray.and.arrow.down")
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .onAppear {
                InvoiceNumberManager.setInitialIfNeeded("2025-1001")
                if selectedClient == nil { selectedClient = clients.first }
                if monthEnd < monthStart { monthEnd = monthStart }
                showServices = !selectedServices.isEmpty

                // Resolve backup folder asynchronously to avoid blocking the main thread
                Task.detached(priority: .utility) {
                    await resolveBackupFolderIfNeededAsync()
                }

                backupObserver = NotificationCenter.default.addObserver(forName: .autoBackupDidFinish, object: nil, queue: .main) { note in
                    if let info = note.userInfo,
                       let msg = info["message"] as? String {
                        self.backupFeedbackMessage = msg
                        self.showBackupFeedback = true
                    }
                }
            }
            .onDisappear {
                if let observer = backupObserver {
                    NotificationCenter.default.removeObserver(observer)
                    backupObserver = nil
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheet(activityItems: payload.items).ignoresSafeArea()
            }
            .sheet(isPresented: $showImportPicker) {
                DocumentPicker { url in
                    do {
                        let report = try Backup.importJSONWithReport(ctx: ctx, url: url)
                        if report.hadLegacyStarred {
                            importInfo = "Imported \(report.importedEntries) entries. Note: This backup was created before starred support; starred items default to not starred."
                            showImportInfo = true
                        }
                    } catch {
                        importError = error.localizedDescription
                        showImportError = true
                    }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView { url in
                    do {
                        // ✅ iOS: create a standard bookmark (no .withSecurityScope on iOS)
                        let bookmark = try url.bookmarkData(
                            options: .minimalBookmark,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        self.backupFolderBookmark = bookmark

                        // Resolve immediately to verify and show name (no .withSecurityScope on iOS)
                        var isStale = false
                        if let resolved = try? URL(
                            resolvingBookmarkData: bookmark,
                            options: [],
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        ) {
                            if isStale,
                               let refreshed = try? resolved.bookmarkData(options: .minimalBookmark,
                                                                           includingResourceValuesForKeys: nil,
                                                                           relativeTo: nil) {
                                self.backupFolderBookmark = refreshed
                            }

                            // Access scope briefly to verify (the URL is security-scoped by virtue of picker grant)
                            let ok = resolved.startAccessingSecurityScopedResource()
                            defer { if ok { resolved.stopAccessingSecurityScopedResource() } }

                            self.resolvedBackupFolderURL = resolved
                            self.importInfo = "Picked folder: \(resolved.lastPathComponent.isEmpty ? resolved.path : resolved.lastPathComponent)"
                            self.showImportInfo = true
                        } else {
                            self.resolvedBackupFolderURL = nil
                            self.importError = "Could not resolve the selected folder. Please try selecting it again."
                            self.showImportError = true
                        }
                    } catch {
                        self.importError = error.localizedDescription
                        self.showImportError = true
                    }
                    // Dismiss the sheet
                    self.showFolderPicker = false
                }
            }
            .alert("Import Failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Unknown error")
            }
            .alert("Import Complete", isPresented: $showImportInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importInfo ?? "Import completed.")
            }
            .alert("Backup", isPresented: $showBackupFeedback) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backupFeedbackMessage ?? "Backup completed.")
            }
        }
    }

    // MARK: - Current selection helpers

    private var currentEntries: [Entry] {
        switch mode {
        case .singleMonth: return entriesForSingleMonth
        case .multiMonth:  return entriesForMultiMonth
        case .dateRange:   return entriesForRange
        }
    }

    private func applyingServiceFilter(_ entries: [Entry]) -> [Entry] {
        guard !selectedServices.isEmpty else { return entries }
        return entries.filter { selectedServices.contains($0.service) }
    }

    private var entriesForSingleMonth: [Entry] {
        guard let c = selectedClient else { return [] }
        let range = monthStart.bdStartOfMonth ... monthStart.bdEndOfMonth
        let base = allEntries.filter { $0.client?.persistentModelID == c.persistentModelID && range.contains($0.serviceDate) }
        return applyingServiceFilter(base)
    }

    private var entriesForMultiMonth: [Entry] {
        guard let c = selectedClient else { return [] }
        let start = min(monthStart.bdStartOfMonth, monthEnd.bdStartOfMonth)
        let end   = max(monthStart.bdEndOfMonth, monthEnd.bdEndOfMonth)
        let base = allEntries.filter { $0.client?.persistentModelID == c.persistentModelID && $0.serviceDate >= start && $0.serviceDate <= end }
        return applyingServiceFilter(base)
    }

    private var entriesForRange: [Entry] {
        guard let c = selectedClient else { return [] }
        let start = min(rangeStart, rangeEnd)
        let end   = max(rangeStart, rangeEnd)
        let base = allEntries.filter { $0.client?.persistentModelID == c.persistentModelID && $0.serviceDate >= start && $0.serviceDate <= end }
        return applyingServiceFilter(base)
    }

    // MARK: - CSV Exports (also create Invoice records) + include notes

    private func exportSingleMonth() {
        guard let c = selectedClient else { return }
        let entries = entriesForSingleMonth

        withNotesTemporarilyAppended(to: includeNotes ? entries : []) {
            if useQuickBooksHeaders {
                let url = CSVExporter.exportQuickBooksSingleInvoice(entries: entries, client: c, terms: "Net 30", invoiceDate: Date())
                sharePayload = SharePayload(items: [url])

                let title = uniqueInvoiceTitle(base: "\(monthStart.yearMonthLabel) Invoice", for: c)
                let inv = Invoice(title: title, number: nil, client: c)
                inv.entriesList.append(contentsOf: entries)
                ctx.insert(inv); try? ctx.save()
            } else {
                let name = "\(c.name)_\(monthStart.yearMonthLabel)"
                let url = CSVExporter.export(entries: entries, fileName: name, headers: headers)
                sharePayload = SharePayload(items: [url])

                let title = uniqueInvoiceTitle(base: "\(monthStart.yearMonthLabel) Invoice", for: c)
                let inv = Invoice(title: title, number: nil, client: c)
                inv.entriesList.append(contentsOf: entries)
                ctx.insert(inv); try? ctx.save()
            }
        }
    }

    private func exportMultiMonth() {
        guard let c = selectedClient else { return }
        let entries = entriesForMultiMonth

        withNotesTemporarilyAppended(to: includeNotes ? entries : []) {
            if useQuickBooksHeaders {
                let cal = Calendar(identifier: .gregorian)
                let groups = Dictionary(grouping: entries) { (e: Entry) -> Date in
                    let comps = cal.dateComponents([.year, .month], from: e.serviceDate)
                    return cal.date(from: comps) ?? e.serviceDate
                }
                let months = groups.keys.sorted()
                var urls: [URL] = []
                for m in months {
                    let monthEntries = (groups[m] ?? []).sorted { $0.serviceDate < $1.serviceDate }
                    let url = CSVExporter.exportQuickBooksSingleInvoice(entries: monthEntries, client: c, terms: "Net 30", invoiceDate: Date())
                    urls.append(url)

                    let title = uniqueInvoiceTitle(base: "\(m.yearMonthLabel) Invoice", for: c)
                    let inv = Invoice(title: title, number: nil, client: c)
                    inv.entriesList.append(contentsOf: monthEntries)
                    ctx.insert(inv)
                }
                try? ctx.save()
                sharePayload = SharePayload(items: urls)
            } else {
                let months = Calendar.current.monthsBetween(start: monthStart, end: monthEnd)
                var urls: [URL] = []
                for m in months {
                    let start = m.bdStartOfMonth, end = m.bdEndOfMonth
                    let monthEntries = entries.filter { $0.serviceDate >= start && $0.serviceDate <= end }
                    let name = "\(c.name)_\(m.yearMonthLabel)"
                    let url = CSVExporter.export(entries: monthEntries, fileName: name, headers: headers)
                    urls.append(url)

                    let title = uniqueInvoiceTitle(base: "\(m.yearMonthLabel) Invoice", for: c)
                    let inv = Invoice(title: title, number: nil, client: c)
                    inv.entriesList.append(contentsOf: monthEntries)
                    ctx.insert(inv)
                }
                try? ctx.save()
                sharePayload = SharePayload(items: urls)
            }
        }
    }

    private func exportRange() {
        guard let c = selectedClient else { return }
        let entries = entriesForRange

        withNotesTemporarilyAppended(to: includeNotes ? entries : []) {
            if useQuickBooksHeaders {
                let url = CSVExporter.exportQuickBooksSingleInvoice(entries: entries, client: c, terms: "Net 30", invoiceDate: Date())
                sharePayload = SharePayload(items: [url])

                let base = "\(min(rangeStart, rangeEnd).yearMonthDay) to \(max(rangeStart, rangeEnd).yearMonthDay) Invoice"
                let title = uniqueInvoiceTitle(base: base, for: c)
                let inv = Invoice(title: title, number: nil, client: c)
                inv.entriesList.append(contentsOf: entries)
                ctx.insert(inv); try? ctx.save()
            } else {
                let start = min(rangeStart, rangeEnd).yearMonthDay
                let end   = max(rangeStart, rangeEnd).yearMonthDay
                let name = "\(c.name)_\(start)_to_\(end)"
                let url = CSVExporter.export(entries: entries, fileName: name, headers: headers)
                sharePayload = SharePayload(items: [url])

                let title = uniqueInvoiceTitle(base: "\(start) to \(end) Invoice", for: c)
                let inv = Invoice(title: title, number: nil, client: c)
                inv.entriesList.append(contentsOf: entries)
                ctx.insert(inv); try? ctx.save()
            }
        }
    }

    /// Temporarily appends notes to `detail` for export, then restores originals (no save).
    private func withNotesTemporarilyAppended(to entries: [Entry], run: () -> Void) {
        guard !entries.isEmpty else { run(); return }
        let originals = entries.map { ($0, $0.detail) }
        for e in entries {
            guard includeNotes, !e.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let note = e.notes.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            e.detail = e.detail.isEmpty ? "Notes: \(note)" : "\(e.detail) — Notes: \(note)"
        }
        run()
        // restore
        for (e, d) in originals { e.detail = d }
    }

    // MARK: - Preview (excludes Done)

    @ViewBuilder
    private func previewSection(entries: [Entry]) -> some View {
        Section("Preview") {
            let notDone = entries.filter { $0.status != .done }
            if notDone.isEmpty {
                Text("No entries to preview.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notDone, id: \.persistentModelID) { e in
                    NavigationLink { EditEntryView(entry: e) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if invoicedEntryIDs.contains(e.persistentModelID) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.green)
                                            .accessibilityLabel("Invoiced")
                                    }
                                    Text(e.clientName).font(.headline)
                                }
                                if !e.detail.isEmpty {
                                    Text(e.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(e.service)
                                Text(e.serviceDate, format: .dateTime.year().month().day())
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Agenda export (includes notes when toggle is on)

    private func exportAgenda() {
        let format = agendaFormatRaw // "plain" | "markdown"
        let ext = (format == "markdown") ? "md" : "txt"

        if agendaScopeRaw == "selectedClient" {
            guard let c = selectedClient else { return }
            let text = agendaText(for: c, format: format)
            let url  = writeText(text, suggestedName: "\(safeFilename(c.name))_Agenda.\(ext)")
            sharePayload = SharePayload(items: [url])
        } else {
            // allClients
            let sorted = clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var blocks: [String] = []
            for c in sorted {
                let (todos, inProg, done) = agendaLists(for: c)
                if todos.isEmpty && inProg.isEmpty && done.isEmpty { continue }
                blocks.append(agendaText(for: c, format: format))
            }
            let allText = blocks.joined(separator: "\n\n")
            let url = writeText(allText, suggestedName: "Agenda.\(ext)")
            sharePayload = SharePayload(items: [url])
        }
    }

    private func copyAgendaToClipboard() {
        let format = agendaFormatRaw
        var text = ""
        if agendaScopeRaw == "selectedClient" {
            if let c = selectedClient { text = agendaText(for: c, format: format) }
        } else {
            let sorted = clients.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            var blocks: [String] = []
            for c in sorted {
                let (todos, inProg, done) = agendaLists(for: c)
                if todos.isEmpty && inProg.isEmpty && done.isEmpty { continue }
                blocks.append(agendaText(for: c, format: format))
            }
            text = blocks.joined(separator: "\n\n")
        }
        if !text.isEmpty { UIPasteboard.general.string = text }
    }

    private func agendaText(for client: Client, format: String) -> String {
        let (todos, inProg, done) = agendaLists(for: client)
        let todoTitle = "TO DO"
        let progTitle = "IN PROGRESS"
        let doneTitle = "DONE (Last 20)"
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)

        switch format {
        case "markdown":
            var lines: [String] = []
            lines.append("# \(client.name) — Agenda")
            lines.append("_\(today)_")
            lines.append("")
            lines.append("## \(todoTitle)")
            lines.append(contentsOf: markdownList(from: todos))
            lines.append("")
            lines.append("## \(progTitle)")
            lines.append(contentsOf: markdownList(from: inProg))
            lines.append("")
            lines.append("## \(doneTitle)")
            lines.append(contentsOf: markdownList(from: done))
            return lines.joined(separator: "\n")

        default: // "plain"
            var lines: [String] = []
            lines.append("\(client.name) — Agenda")
            lines.append("_\(today)_")
            lines.append("")
            lines.append("\(todoTitle):")
            lines.append(contentsOf: plainList(from: todos))
            lines.append("")
            lines.append("\(progTitle):")
            lines.append(contentsOf: plainList(from: inProg))
            lines.append("")
            lines.append("\(doneTitle):")
            lines.append(contentsOf: plainList(from: done))
            return lines.joined(separator: "\n")
        }
    }

    private func plainList(from entries: [Entry]) -> [String] {
        if entries.isEmpty { return ["• (none)"] }
        return entries.map { bulletLine(for: $0) }
    }

    private func markdownList(from entries: [Entry]) -> [String] {
        if entries.isEmpty { return ["- _(none)_"] }
        return entries.map { "- \(markdownLine(for: $0))" }
    }

    private func bulletLine(for e: Entry) -> String {
        let svc  = e.service.isEmpty ? "—" : e.service
        let desc = e.detail.isEmpty ? "No description" : e.detail.replacingOccurrences(of: "\n", with: " ")
        var line = "• \(svc) — \(desc)"
        if includeNotes, !e.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = e.notes.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            line += " — \(note)"
        }
        if includeSubtasks {
            let completed = e.subtasksList.filter { $0.isDone }
            if !completed.isEmpty {
                let bullets = completed.map { "  ✓ \($0.title)" }.joined(separator: "\n")
                line += "\n" + bullets
            }
        }
        return line
    }

    private func markdownLine(for e: Entry) -> String {
        let svc  = e.service.isEmpty ? "—" : e.service
        let desc = e.detail.isEmpty ? "No description" : e.detail.replacingOccurrences(of: "\n", with: " ")
        var line = "**\(svc)** — \(desc)"
        if includeNotes, !e.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = e.notes.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            line += " — \(note)"
        }
        if includeSubtasks {
            let completed = e.subtasksList.filter { $0.isDone }
            if !completed.isEmpty {
                let bullets = completed.map { "  - ~~\($0.title)~~" }.joined(separator: "\n")
                line += "\n" + bullets
            }
        }
        return line
    }

    /// (To Do, In Progress, Done-last-20). Done respects service filter and ignores date scope.
    private func agendaLists(for client: Client) -> (todos: [Entry], inProg: [Entry], done: [Entry]) {
        let clientEntries = allEntries.filter { $0.client?.persistentModelID == client.persistentModelID }
        let filtered = applyingServiceFilter(clientEntries)

        let sortedActive = filtered.sorted {
            if $0.service.caseInsensitiveCompare($1.service) == .orderedSame {
                if $0.detail.caseInsensitiveCompare($1.detail) == .orderedSame {
                    return $0.serviceDate < $1.serviceDate
                }
                return $0.detail.localizedCaseInsensitiveCompare($1.detail) == .orderedAscending
            }
            return $0.service.localizedCaseInsensitiveCompare($1.service) == .orderedAscending
        }

        var todos: [Entry] = []
        var inProg: [Entry] = []
        for e in sortedActive {
            switch e.status {
            case .done: break
            case .inProgress: inProg.append(e)
            case .todo: todos.append(e)
            }
        }

        let doneAll = filtered.filter { $0.status == .done }
        let doneSorted = doneAll.sorted {
            let d0 = $0.completedAt ?? $0.serviceDate
            let d1 = $1.completedAt ?? $1.serviceDate
            return d0 > d1
        }
        let doneTop20 = Array(doneSorted.prefix(20))

        return (todos, inProg, doneTop20)
    }

    @discardableResult
    private func writeText(_ text: String, suggestedName: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func safeFilename(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return s.components(separatedBy: bad).joined(separator: "_")
    }
    
    private func pickBackupFolder() {
        // Ensure JSON import sheet is not presented
        showImportPicker = false
        DispatchQueue.main.async {
            showFolderPicker = true
        }
    }

    // ✅ Resolve stored bookmark asynchronously (no .withSecurityScope on iOS)
    @MainActor
    private func resolveBackupFolderIfNeededAsync() async {
        guard let data = backupFolderBookmark else {
            resolvedBackupFolderURL = nil
            return
        }

        // Perform potentially blocking iCloud operations off the main thread
        let result: (url: URL?, refreshedBookmark: Data?) = await Task.detached(priority: .utility) {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                return (nil, nil)
            }
            var refreshedBookmark: Data? = nil
            if isStale {
                refreshedBookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            return (url, refreshedBookmark)
        }.value

        // Update UI state on main thread
        if let refreshed = result.refreshedBookmark {
            backupFolderBookmark = refreshed
        }
        resolvedBackupFolderURL = result.url
    }

    // Synchronous version kept for internal use where already on background thread
    private func resolveBackupFolderIfNeeded() {
        guard let data = backupFolderBookmark else { resolvedBackupFolderURL = nil; return }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            if isStale,
               let refreshed = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                backupFolderBookmark = refreshed
            }
            resolvedBackupFolderURL = url
        } else {
            resolvedBackupFolderURL = nil
        }
    }

    // ✅ Hydrate iCloud folders and coordinate writes (async to avoid blocking main thread)
    private func writeTestBackupToChosenFolder() {
        guard let folderURL = resolvedBackupFolderURL else { return }
        guard let data = try? Backup.makeJSONData(ctx: ctx) else { return }

        // Dispatch potentially blocking iCloud/file coordinator operations to background
        DispatchQueue.global(qos: .userInitiated).async {
            // Begin security scope (the URL retains the file provider security scope from the picker)
            let started = folderURL.startAccessingSecurityScopedResource()
            defer { if started { folderURL.stopAccessingSecurityScopedResource() } }

            do {
                // If the picked folder is in iCloud Drive, nudge hydration
                try ensureUbiquitousFolderReady(folderURL)

                let name = Backup.defaultBackupName() + ".json"
                let dest = folderURL.appendingPathComponent(name)

                // Coordinate write (safer with iCloud & file providers)
                let coordinator = NSFileCoordinator()
                var tempError: NSError?
                var writeError: Error?

                coordinator.coordinate(writingItemAt: dest, options: [], error: &tempError) { url in
                    do {
                        try data.write(to: url, options: .atomic)
                    } catch {
                        // Capture write error locally to avoid overlapping access on tempError
                        writeError = error
                    }
                }

                // Check for coordination or write errors
                if let err = tempError { throw err }
                if let err = writeError { throw err }

                let savedName = dest.lastPathComponent
                DispatchQueue.main.async {
                    self.importInfo = "Saved backup to: \(savedName)"
                    self.showImportInfo = true
                }
            } catch {
                let errorMessage = error.localizedDescription
                DispatchQueue.main.async {
                    self.importError = errorMessage
                    self.showImportError = true
                }
            }
        }
    }

    private func ensureUbiquitousFolderReady(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            // Kick off a download if needed; the coordinated write will wait if necessary
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    private func uniqueInvoiceTitle(base: String, for client: Client) -> String {
        let baseTrim = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetched: [Invoice] = (try? ctx.fetch(FetchDescriptor<Invoice>())) ?? []
        let clientInvoices = fetched.filter { $0.client?.persistentModelID == client.persistentModelID }
        let count = clientInvoices.filter { $0.title.hasPrefix(baseTrim) }.count
        return count == 0 ? baseTrim : "\(baseTrim) \(count + 1)"
    }
} // 👈 END of ExportView

// MARK: - Folder Picker (file-scope)
private struct FolderPickerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIDocumentPickerViewController
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // No-op; dismissal handled by the presenting sheet
        }
    }
}

