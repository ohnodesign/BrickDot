// Views/SettingsView.swift
import SwiftUI

// MARK: - Keys used across the app
enum AppPrefsKey {
    // Home & Sections
    static let homeShowStarred      = "home.showStarred"
    static let homeShowTodo         = "home.showTodo"
    static let homeShowInProgress   = "home.showInProgress"
    static let homeShowDone         = "home.showDone"
    static let homeShowRecent       = "home.showRecent"

    // Exports & Agenda
    static let exportQBHeaders      = "export.useQuickBooksHeaders"
    static let exportIncludeNotes   = "export.includeNotes"       // ← NEW
    static let agendaScope          = "agenda.defaultScope"       // "selectedClient" | "allClients"
    static let agendaFormat         = "agenda.defaultFormat"      // "plain" | "markdown"
    static let csvDelimiter         = "agenda.csvDelimiter"       // "comma" | "semicolon"

    // Time & Timer
    static let defaultHourlyRate    = "time.defaultHourlyRate"
    static let roundingIncrement    = "time.roundingIncrement"    // "min5" | "min10" | "min15"
    static let timerAutoStart       = "time.timer.autoStartOnInProgress"
    static let timerPromptOnPause   = "time.timer.promptOnPause"
    static let timerLiveActivity    = "time.timer.liveActivity"

    // Appearance
    static let accentPreset         = "appearance.accentPreset"   // "blue"|"indigo"|"brick"|"green"|"orange"
    static let colorScheme          = "appearance.colorScheme"    // "system"|"light"|"dark"
    static let largeControls        = "appearance.largeControls"
    static let increasedContrast    = "appearance.increasedContrast"

    // Data & Backup
    static let autoBackupICloud     = "backup.autoIcloud"

    // Invoicing
    static let invoiceTerms         = "invoice.defaultTerms"
    static let invoicePrefix        = "invoice.numberPrefix"
    static let invoiceNextNumber    = "invoice.nextNumber"
    static let invoiceTaxRate       = "invoice.defaultTaxRate"
    static let invoiceDiscountRate  = "invoice.defaultDiscountRate"
}

// MARK: - Settings screen
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showImportPicker = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showResetConfirmation = false
    @State private var showICloudImportWarning = false

    // Home & Sections
    @AppStorage(AppPrefsKey.homeShowStarred)    private var showStarred = true
    @AppStorage(AppPrefsKey.homeShowTodo)       private var showTodo = false
    @AppStorage(AppPrefsKey.homeShowInProgress) private var showInProgress = false
    @AppStorage(AppPrefsKey.homeShowDone)       private var showDone = false
    @AppStorage(AppPrefsKey.homeShowRecent)     private var showRecent = false
    @AppStorage("home.recentCount") private var homeRecentCount: Int = 10

    // Exports & Agenda
    @AppStorage(AppPrefsKey.exportQBHeaders)    private var useQBHeaders = true
    @AppStorage(AppPrefsKey.exportIncludeNotes) private var includeNotes = false   // ← NEW
    @AppStorage(AppPrefsKey.agendaScope)        private var agendaScopeRaw = "selectedClient" // or "allClients"
    @AppStorage(AppPrefsKey.agendaFormat)       private var agendaFormatRaw = "plain"         // or "markdown"
    @AppStorage(AppPrefsKey.csvDelimiter)       private var csvDelimiterRaw = "comma"         // or "semicolon"

    // Time & Timer
    @AppStorage(AppPrefsKey.defaultHourlyRate)  private var defaultRate: Double = 100
    @AppStorage(AppPrefsKey.roundingIncrement)  private var roundingRaw = "min15" // "min5"/"min10"/"min15"
    @AppStorage(AppPrefsKey.timerAutoStart)     private var timerAutoStart = true
    @AppStorage(AppPrefsKey.timerPromptOnPause) private var timerPromptOnPause = true
    @AppStorage(AppPrefsKey.timerLiveActivity)  private var timerLiveActivity = false

    // Appearance
    @AppStorage(AppPrefsKey.accentPreset)       private var accentRaw = "indigo"
    @AppStorage(AppPrefsKey.colorScheme)        private var appearanceRaw = "system"
    @AppStorage(AppPrefsKey.largeControls)      private var largeControls = false
    @AppStorage(AppPrefsKey.increasedContrast)  private var increasedContrast = false
    @AppStorage("appearance.theme")             private var themeRaw = "professional"

    // Data & Backup
    @AppStorage(AppPrefsKey.autoBackupICloud)   private var autoBackupIcloud = false

    // Invoicing
    @AppStorage(AppPrefsKey.invoiceTerms)       private var invoiceTerms = "Net 30"
    @AppStorage(AppPrefsKey.invoicePrefix)      private var invoicePrefix = "INV-"
    @AppStorage(AppPrefsKey.invoiceNextNumber)  private var invoiceNextNumber = 1001
    @AppStorage(AppPrefsKey.invoiceTaxRate)     private var invoiceTaxRate: Double = 0.00
    @AppStorage(AppPrefsKey.invoiceDiscountRate) private var invoiceDiscountRate: Double = 0.00

    var body: some View {
        Form {
            // Home & Sections
            Section("Home & Sections") {
                Toggle("Expand Starred by default", isOn: $showStarred)
                Toggle("Expand To Do by default", isOn: $showTodo)
                Toggle("Expand In Progress by default", isOn: $showInProgress)
                Toggle("Expand Done by default", isOn: $showDone)
                Toggle("Show Recent section by default", isOn: $showRecent)
                HStack {
                    Text("Recent items on Home")
                    Spacer()
                    Stepper(value: $homeRecentCount, in: 0...100) {
                        EmptyView()
                    }
                    .labelsHidden()
                    TextField("0", value: $homeRecentCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                }
            }

            // Exports & Agenda
            Section("Exports & Agenda") {
                Toggle("Use QuickBooks-style headers by default", isOn: $useQBHeaders)
                Toggle("Include notes in exports", isOn: $includeNotes) // ← NEW

                Picker("Default scope", selection: $agendaScopeRaw) {
                    Text("Selected Client").tag("selectedClient")
                    Text("All Clients").tag("allClients")
                }
                Picker("Default format", selection: $agendaFormatRaw) {
                    Text("Plain Text").tag("plain")
                    Text("Markdown").tag("markdown")
                }
                Picker("CSV delimiter", selection: $csvDelimiterRaw) {
                    Text("Comma (,)").tag("comma")
                    Text("Semicolon (;)").tag("semicolon")
                }
            }

            // Time & Timer
            Section("Time & Timer") {
                numberField(title: "Default hourly rate", value: $defaultRate)
                Picker("Rounding (Add Time)", selection: $roundingRaw) {
                    Text("5 minutes").tag("min5")
                    Text("10 minutes").tag("min10")
                    Text("15 minutes").tag("min15")
                }
                Toggle("Auto-start when status becomes In Progress", isOn: $timerAutoStart)
                Toggle("Prompt to log elapsed time when pausing", isOn: $timerPromptOnPause)
                Toggle("Live Activity", isOn: $timerLiveActivity)
            }

            // Appearance
            Section("Appearance") {
                Picker("Accent color", selection: $accentRaw) {
                    accentRow("blue"); accentRow("indigo"); accentRow("brick"); accentRow("green"); accentRow("orange")
                }
                Picker("Theme", selection: $appearanceRaw) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Color Scheme", selection: $themeRaw) {
                    ForEach(ThemeKey.allCases, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                Toggle("Large controls", isOn: $largeControls)
                Toggle("Increased contrast", isOn: $increasedContrast)
            }

            // Data & Backup
            Section("Data & Backup") {
                Button("Export backup (JSON)") { exportBackup() }
                Button("Import backup (JSON)") { importBackup() }
                Toggle("Auto-backup to iCloud Drive", isOn: $autoBackupIcloud)
                Button(role: .destructive) { showResetConfirmation = true } label: { Text("Reset all data") }
            }

            // Invoicing Defaults
            Section("Invoicing Defaults") {
                TextField("Default terms", text: $invoiceTerms)
                TextField("Invoice numbering prefix", text: $invoicePrefix)
                Stepper(value: $invoiceNextNumber, in: 1...9_999_999) { Text("Next invoice number: \(invoiceNextNumber)") }
                numberField(title: "Default tax rate (%)", value: $invoiceTaxRate)
                numberField(title: "Default discount (%)", value: $invoiceDiscountRate)
            }

            // About
            Section("About") {
                HStack { Text("Version"); Spacer(); Text(versionString()).foregroundStyle(.secondary) }
                Link("Support", destination: URL(string: "https://ohnodesign.com/support")!)
                Link("Privacy", destination: URL(string: "https://ohnodesign.com/privacy")!)
                Link("Website", destination: URL(string: "https://ohnodesign.com")!)
            }
        }
        .navigationTitle("Settings")
        .dynamicTypeSize(largeControls ? .accessibility2 : .large)
        .sheet(isPresented: $showImportPicker) {
            DocumentPicker { url in
                performImport(url: url)
            }
        }
        .sheet(isPresented: $showExportShare) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("iCloud Sync Active", isPresented: $showICloudImportWarning) {
            Button("Import Anyway") { showImportPicker = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("iCloud sync is enabled. Importing a backup may create duplicate entries if the same data exists in iCloud. Consider disabling iCloud sync before importing.")
        }
        .confirmationDialog("Delete all clients, entries, and related data? This cannot be undone.", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { performReset() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Helpers
    @ViewBuilder
    private func numberField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title); Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }
    @ViewBuilder private func accentRow(_ key: String) -> some View {
        HStack { Circle().fill(accentColor(from: key)).frame(width: 16, height: 16); Text(key.capitalized) }.tag(key)
    }
    private func accentColor(from key: String) -> Color {
        switch key { case "blue": return .blue; case "indigo": return .indigo; case "brick": return .brick; case "green": return .green; case "orange": return .orange; default: return .indigo }
    }
    private func exportBackup() {
        do {
            let url = try Backup.exportJSON(ctx: modelContext)
            exportURL = url
            showExportShare = true
        } catch {
            alertTitle = "Export Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func importBackup() {
        if autoBackupIcloud {
            showICloudImportWarning = true
        } else {
            showImportPicker = true
        }
    }

    private func performImport(url: URL) {
        do {
            let report = try Backup.importJSONWithReport(ctx: modelContext, url: url)
            alertTitle = "Import Complete"
            var msg = "Imported \(report.importedClients) new client(s) and \(report.importedEntries) entry/entries."
            if report.hadLegacyStarred {
                msg += "\n\nSome entries came from an older backup without starred info — they default to unstarred."
            }
            alertMessage = msg
            showAlert = true
        } catch {
            alertTitle = "Import Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func performReset() {
        do {
            let backupURL = try Backup.exportJSON(ctx: modelContext, fileName: "PreReset_\(Backup.defaultBackupName())")
            // Delete children first to avoid orphaned rows
            // (batch delete may not trigger cascade rules)
            try modelContext.delete(model: Subtask.self)
            try modelContext.delete(model: TimeLog.self)
            try modelContext.delete(model: TemplateSubtask.self)
            try modelContext.delete(model: Entry.self)
            try modelContext.delete(model: Invoice.self)
            try modelContext.delete(model: EntryTemplate.self)
            try modelContext.delete(model: Client.self)
            try modelContext.save()
            alertTitle = "Reset Complete"
            alertMessage = "All data has been deleted.\n\nA safety backup was saved to:\n\(backupURL.lastPathComponent)"
            showAlert = true
        } catch {
            alertTitle = "Reset Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
    private func versionString() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }
}
