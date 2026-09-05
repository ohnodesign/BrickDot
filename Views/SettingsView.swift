// Views/SettingsView.swift
import SwiftUI
import UIKit
import SwiftData

// MARK: - Keys used across the app
enum AppPrefsKey {
    // Time
    static let roundingIncrement    = "time.roundingIncrement"    // "min5" | "min10" | "min15"

    // Appearance
    static let colorScheme          = "appearance.colorScheme"    // "system"|"light"|"dark"
    static let showDailyPhrase      = "appearance.showDailyPhrase"

    // Notifications
    static let notificationsEnabled = "notifications.enabled"
    static let notifyDueToday       = "notifications.dueToday"
    static let notifyOverdue        = "notifications.overdue"
    static let notifyNoTimeLogged   = "notifications.noTimeLogged"
    static let notifyCOMMReply      = "notifications.commReply"
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

    @State private var apiKey = AIService.apiKey

    // Time
    @AppStorage(AppPrefsKey.roundingIncrement)  private var roundingRaw = "min15"

    // Appearance
    @AppStorage(AppPrefsKey.colorScheme)        private var appearanceRaw = "system"
    @AppStorage(AppPrefsKey.showDailyPhrase)    private var showDailyPhrase = true
    @AppStorage("appearance.theme")             private var themeRaw = "professional"

    // Notifications
    @AppStorage(AppPrefsKey.notificationsEnabled) private var notificationsEnabled = false
    @AppStorage(AppPrefsKey.notifyDueToday)       private var notifyDueToday = true
    @AppStorage(AppPrefsKey.notifyOverdue)         private var notifyOverdue = true
    @AppStorage(AppPrefsKey.notifyNoTimeLogged)    private var notifyNoTimeLogged = true
    @AppStorage(AppPrefsKey.notifyCOMMReply)       private var notifyCOMMReply = true
    @AppStorage(AutoBackup.Schedule.enabledKey)    private var autoBackupEnabled = true

    var body: some View {
        Form {
            // Time & Appearance
            Section("Time") {
                Picker("Rounding (Add Time)", selection: $roundingRaw) {
                    Text("5 minutes").tag("min5")
                    Text("10 minutes").tag("min10")
                    Text("15 minutes").tag("min15")
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(ThemeKey.allCases, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                Picker("Mode", selection: $appearanceRaw) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Toggle("Daily inspiration phrase", isOn: $showDailyPhrase)
            }

            Section("Notifications") {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.shared.requestPermission()
                        }
                    }
                if notificationsEnabled {
                    Toggle("Due today (8:00 AM)", isOn: $notifyDueToday)
                    Toggle("Overdue items (9:00 AM)", isOn: $notifyOverdue)
                    Toggle("No time logged (6:00 PM)", isOn: $notifyNoTimeLogged)
                    Toggle("COMM needs reply", isOn: $notifyCOMMReply)
                }
            }

            Section("AI Coach") {
                SecureField("Anthropic API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: apiKey) { _, newValue in
                        AIService.apiKey = newValue
                    }
                if apiKey.isEmpty {
                    Text("Get a key at console.anthropic.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            #if targetEnvironment(macCatalyst)
            CoachBridgeSection()
            #endif

            // Data & Backup
            Section("Data & Backup") {
                Toggle("Automatic daily backup", isOn: $autoBackupEnabled)
                Button("Export backup (JSON)") { exportBackup() }
                Button("Import backup (JSON)") { showImportPicker = true }
                Button(role: .destructive) { showResetConfirmation = true } label: { Text("Reset all data") }
            }

            // Services (collapsed by default)
            ServicesSection()

            // About
            Section("About") {
                HStack { Text("Version"); Spacer(); Text(versionString()).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Settings")
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
        .confirmationDialog("Delete all clients, entries, and related data? This cannot be undone.", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { performReset() }
            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Helpers

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

// MARK: - Services Editor

private struct ServicesSection: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var services: [String] = Constants.services
    @State private var newService = ""
    @State private var editingIndex: Int? = nil
    @State private var editingText = ""
    @State private var expanded = false

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [GridItem(.flexible()), GridItem(.flexible())]
        } else {
            return [GridItem(.flexible())]
        }
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(services.enumerated()), id: \.offset) { index, svc in
                        if editingIndex == index {
                            HStack {
                                TextField("Service name", text: $editingText)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .onSubmit { commitEdit(at: index) }
                                Button("Done") { commitEdit(at: index) }
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray5)))
                        } else {
                            HStack {
                                Text(svc).font(.subheadline)
                                Spacer()
                                Button {
                                    editingIndex = index
                                    editingText = svc
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    services.remove(at: index)
                                    save()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                        }
                    }
                }

                HStack {
                    TextField("New service", text: $newService)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { addService() }
                    Button {
                        addService()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.accent)
                    }
                    .disabled(newService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text("Services")
                    Spacer()
                    Text("\(services.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if expanded {
                Text("Tap the pencil to rename. Tap ✕ to delete.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealServicesEditor)) { _ in
            withAnimation { expanded = true }
        }
    }

    private func addService() {
        let trimmed = newService.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !services.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newService = ""
            return
        }
        services.append(trimmed)
        newService = ""
        save()
    }

    private func commitEdit(at index: Int) {
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !services.enumerated().contains(where: { $0.offset != index && $0.element.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            services[index] = trimmed
            save()
        }
        editingIndex = nil
        editingText = ""
    }

    private func save() {
        Constants.services = services
    }
}


// MARK: - Claude Bridge (Mac only)

#if targetEnvironment(macCatalyst)
/// Lets a Claude conversation on this Mac read and change BrickDot through a
/// loopback socket. Off by default: it speaks for the whole database.
private struct CoachBridgeSection: View {
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var server = CoachBridgeServer.shared

    @State private var enabled = CoachBridge.isEnabled
    @State private var readOnly = CoachBridge.isReadOnly
    @State private var revealToken = false

    var body: some View {
        Section {
            Toggle("Allow Claude to connect", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    CoachBridge.isEnabled = on
                    if on {
                        server.start(container: ctx.container)
                    } else {
                        server.stop()
                    }
                }

            if enabled {
                Toggle("Read-only", isOn: $readOnly)
                    .onChange(of: readOnly) { _, on in CoachBridge.isReadOnly = on }

                LabeledContent("Status") {
                    Text(server.isRunning ? "Listening on \(CoachBridge.port)" : "Not running")
                        .foregroundStyle(server.isRunning ? .green : .secondary)
                }

                if let error = server.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(revealToken ? "Hide token" : "Show connection token") {
                    revealToken.toggle()
                }

                if revealToken {
                    Text(CoachBridge.token)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy token") {
                        UIPasteboard.general.string = CoachBridge.token
                    }
                    Button("Regenerate token", role: .destructive) {
                        CoachBridge.regenerateToken()
                        revealToken = false
                    }
                }
            }
        } header: {
            Text("Claude Bridge")
        } footer: {
            Text(enabled
                 ? "Claude can reach BrickDot at 127.0.0.1:\(CoachBridge.port) while the app is running. Paste the token into your MCP config."
                 : "Off. Turn on to let a Claude conversation on this Mac look up tasks and log work.")
        }
    }
}
#endif
