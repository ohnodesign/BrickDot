import SwiftUI
import SwiftData

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    @Query(sort: \Client.name) private var clients: [Client]

    @State private var selectedClient: Client?
    @State private var service: String = Constants.services.first ?? ""
    @State private var detail: String = ""
    @State private var rawInput: String = ""
    @State private var isSaving = false
    @State private var showFullEntry = false
    @State private var showManualPickers = false
    @State private var parsedPreview: ParsedInput?

    @StateObject private var speech = SpeechRecognizer()

    @AppStorage("quickadd.lastClientName") private var lastClientName = ""
    @AppStorage("quickadd.lastService") private var lastService = ""

    @FocusState private var inputFocused: Bool

    var prefillClient: Client? = nil
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Quick Entry field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Entry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    HStack {
                        TextField("cs photo fix drain 15m done", text: $rawInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($inputFocused)
                            .onChange(of: rawInput) { _, _ in parseInput() }
                            .onSubmit { if canSave { save() } }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))

                        Button {
                            if speech.isRecording {
                                speech.stopRecording()
                            } else {
                                Task {
                                    let ok = await speech.requestPermission()
                                    if ok { speech.transcript = ""; speech.startRecording() }
                                }
                            }
                        } label: {
                            Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                                .foregroundStyle(speech.isRecording ? theme.overdue : theme.accent)
                                .imageScale(.large)
                                .frame(width: 44, height: 44)
                        }
                    }

                    if speech.isRecording {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Listening…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if let error = speech.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                // Parsed preview
                if let parsed = parsedPreview {
                    HStack(spacing: 8) {
                        Circle().fill(parsed.client.accentColor).frame(width: 10, height: 10)
                        Text(parsed.client.name).font(.subheadline.weight(.semibold))
                        if !parsed.service.isEmpty {
                            Text(parsed.service).font(.caption).foregroundStyle(.secondary)
                        }
                        if !parsed.description.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            Text(parsed.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if parsed.hours > 0 {
                            Text("·").foregroundStyle(.secondary)
                            Text(formatHours(parsed.hours)).font(.caption.weight(.medium)).foregroundStyle(theme.accent)
                        }
                        if parsed.isDone {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.accentLight.opacity(0.35)))
                } else if rawInput.count >= 2 {
                    Text("No match — try a different shortcode or use Pick Manually")
                        .font(.caption).foregroundStyle(.orange)
                }

                if clients.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Add a client first from the Clients tab, or use Full Entry to create one inline.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                }

                // Quick Save button
                Button(action: save) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 24, height: 24)
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isSaving ? "Saving…" : "Quick Save")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canSave ? theme.quickCapture : Color(.systemGray4))
                    )
                    .foregroundStyle(theme.buttonText)
                }
                .disabled(!canSave || isSaving)

                // Alternative entry buttons
                HStack(spacing: 12) {
                    Button {
                        showManualPickers = true
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Pick Manually")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.sidebarBackground))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFullEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("Full Entry")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.sidebarBackground))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.stopRecording(); dismiss() }
                }
            }
            .onAppear {
                if let pre = prefillClient {
                    selectedClient = pre
                } else if let last = clients.first(where: { $0.name == lastClientName }) {
                    selectedClient = last
                } else {
                    selectedClient = clients.first
                }
                if !lastService.isEmpty && Constants.services.contains(lastService) {
                    service = lastService
                }
                inputFocused = true
            }
            .onChange(of: speech.transcript) { _, newValue in
                if speech.isRecording { rawInput = newValue }
            }
            .onDisappear { speech.stopRecording() }
            .sheet(isPresented: $showFullEntry) {
                NavigationStack {
                    NewEntryView(
                        onSaved: { showFullEntry = false; onSaved?(); dismiss() },
                        prefillClient: effectiveClient,
                        prefillService: effectiveService,
                        prefillDetail: effectiveDetail
                    )
                }
            }
            .sheet(isPresented: $showManualPickers) {
                ManualPickerSheet(
                    clients: clients,
                    selectedClient: $selectedClient,
                    service: $service,
                    detail: $detail,
                    onSave: { save() }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Shorthand Parser

    private struct ParsedInput {
        let client: Client
        let service: String
        let description: String
        let hours: Double
        let isDone: Bool
    }

    private func parseInput() {
        let cleaned = rawInput.replacingOccurrences(of: #"[.,!?;:]"#, with: "", options: .regularExpression)
        let words = cleaned.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard !words.isEmpty else { parsedPreview = nil; return }

        let clientQuery = String(words[0]).lowercased()
        guard let matchedClient = matchClient(clientQuery) else { parsedPreview = nil; return }

        var matchedService = ""
        var rawDesc = ""

        if words.count >= 2 {
            let serviceQuery = String(words[1]).lowercased()
            rawDesc = words.count > 2 ? String(words[2]) : ""

            // Try combining service word with start of description for multi-word service names
            // e.g. "web update" → "webupdate" matches "WEBUP" better than just "web"
            if !rawDesc.isEmpty {
                let descWords = rawDesc.split(separator: " ")
                let combined = serviceQuery + descWords[0].lowercased()
                if let match = matchService(combined) {
                    matchedService = match
                    rawDesc = descWords.dropFirst().joined(separator: " ")
                } else {
                    matchedService = matchService(serviceQuery) ?? ""
                }
            } else {
                matchedService = matchService(serviceQuery) ?? ""
            }
        }

        let (desc, hours, isDone) = extractTimeAndStatus(from: rawDesc)
        parsedPreview = ParsedInput(client: matchedClient, service: matchedService, description: desc, hours: hours, isDone: isDone)
    }

    private static let wordNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12
    ]

    private func extractTimeAndStatus(from text: String) -> (description: String, hours: Double, isDone: Bool) {
        var remaining = text
        var hours: Double = 0

        let naturalPatterns: [(pattern: String, hours: Double)] = [
            (#"\b(three\s+quarters?\s+of\s+an?\s+hour|three\s+quarter\s+hours?)\b"#, 0.75),
            (#"\b(quarter\s+of\s+an?\s+hour|quarter\s+hour)\b"#, 0.25),
            (#"\bhalf\s+an?\s+hour\b"#, 0.5),
            (#"\ban?\s+hour\s+and\s+a\s+half\b"#, 1.5),
        ]

        for (pattern, value) in naturalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(remaining.startIndex..., in: remaining)
                if let match = regex.firstMatch(in: remaining, range: range) {
                    hours = value
                    remaining = remaining.replacingCharacters(in: Range(match.range, in: remaining)!, with: "")
                    break
                }
            }
        }

        // "one hour", "two hours", "three minutes", etc.
        if hours == 0 {
            let wordNumPattern = #"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+(hours?|hrs?|minutes?|mins?)\b"#
            if let regex = try? NSRegularExpression(pattern: wordNumPattern, options: .caseInsensitive) {
                let range = NSRange(remaining.startIndex..., in: remaining)
                if let match = regex.firstMatch(in: remaining, range: range),
                   let numRange = Range(match.range(at: 1), in: remaining),
                   let unitRange = Range(match.range(at: 2), in: remaining),
                   let value = Self.wordNumbers[remaining[numRange].lowercased()] {
                    let unit = remaining[unitRange].lowercased()
                    hours = unit.hasPrefix("h") ? value : value / 60.0
                    remaining = remaining.replacingCharacters(in: Range(match.range, in: remaining)!, with: "")
                }
            }
        }

        // Numeric: 15 minutes, 1.5 hours, 2h, 30m, .5 hr, 90min
        if hours == 0 {
            let durationPattern = #"(\d+\.?\d*|\.\d+)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#
            if let regex = try? NSRegularExpression(pattern: durationPattern, options: .caseInsensitive) {
                let range = NSRange(remaining.startIndex..., in: remaining)
                if let match = regex.firstMatch(in: remaining, range: range),
                   let numRange = Range(match.range(at: 1), in: remaining),
                   let unitRange = Range(match.range(at: 2), in: remaining),
                   let value = Double(remaining[numRange]) {
                    let unit = remaining[unitRange].lowercased()
                    hours = unit.hasPrefix("h") ? value : value / 60.0
                    remaining = remaining.replacingCharacters(in: Range(match.range, in: remaining)!, with: "")
                }
            }
        }

        var isDone = false
        let donePattern = #"\b(done|complete|completed|finished)\b"#
        if let regex = try? NSRegularExpression(pattern: donePattern, options: .caseInsensitive) {
            let range = NSRange(remaining.startIndex..., in: remaining)
            if let match = regex.firstMatch(in: remaining, range: range) {
                isDone = true
                remaining = remaining.replacingCharacters(in: Range(match.range, in: remaining)!, with: "")
            }
        }

        remaining = remaining.split(separator: " ").joined(separator: " ")

        return (remaining, hours, isDone)
    }

    private func matchClient(_ query: String) -> Client? {
        if let match = clients.first(where: { !$0.shortcode.isEmpty && $0.shortcode.lowercased() == query }) { return match }
        if let match = clients.first(where: { !$0.shortcode.isEmpty && $0.shortcode.lowercased().hasPrefix(query) }) { return match }
        if let match = clients.first(where: { $0.name.lowercased().hasPrefix(query) }) { return match }
        if let match = clients.first(where: {
            let initials = $0.name.split(separator: " ").compactMap({ $0.first }).map({ String($0).lowercased() }).joined()
            return initials.hasPrefix(query)
        }) { return match }
        if let match = clients.first(where: { $0.name.lowercased().contains(query) }) { return match }
        return nil
    }

    private func matchService(_ query: String) -> String? {
        if let exact = Constants.services.first(where: { $0.lowercased() == query }) { return exact }
        let matches = Constants.services.filter { $0.lowercased().hasPrefix(query) }
        if matches.count == 1 { return matches[0] }
        return matches.min(by: { $0.count < $1.count })
    }

    // MARK: - Effective values

    private var effectiveClient: Client? { parsedPreview?.client ?? selectedClient }
    private var effectiveService: String { parsedPreview?.service ?? service }
    private var effectiveDetail: String {
        if let parsed = parsedPreview, !parsed.description.isEmpty { return parsed.description }
        return detail
    }
    private var effectiveHours: Double { parsedPreview?.hours ?? 0 }
    private var effectiveStatus: EntryStatus { parsedPreview?.isDone == true ? .done : .todo }
    private var canSave: Bool { effectiveClient != nil }

    private func formatHours(_ h: Double) -> String {
        let totalMinutes = Int(round(h * 60))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        } else if totalMinutes % 60 == 0 {
            return "\(totalMinutes / 60)h"
        } else {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
    }

    private func save() {
        guard let client = effectiveClient, !isSaving else { return }
        isSaving = true

        let isDone = effectiveStatus == .done
        let entry = Entry(
            serviceDate: Date(),
            service: effectiveService,
            detail: effectiveDetail.trimmingCharacters(in: .whitespacesAndNewlines),
            hours: effectiveHours,
            rate: client.rate,
            client: client,
            status: effectiveStatus,
            createdAt: Date(),
            completedAt: isDone ? Date() : nil,
            isImportant: !isDone
        )
        entry.isQuickAdd = true
        ctx.insert(entry)

        if effectiveHours > 0 {
            let log = TimeLog(hours: effectiveHours, note: "Quick add", entry: entry)
            entry.timeLogsList.append(log)
        }

        do {
            try ctx.save()
            lastClientName = client.name
            lastService = effectiveService
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isSaving = false
            onSaved?()
            dismiss()
        } catch {
            isSaving = false
        }
    }
}

// MARK: - Manual Picker Sheet

private struct ManualPickerSheet: View {
    let clients: [Client]
    @Binding var selectedClient: Client?
    @Binding var service: String
    @Binding var detail: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Client", selection: $selectedClient) {
                    ForEach(clients, id: \.persistentModelID) { c in
                        Text(c.name).tag(Optional(c))
                    }
                }
                Picker("Service", selection: $service) {
                    ForEach(Constants.services, id: \.self) { s in
                        Text(s).tag(s)
                    }
                }
                TextField("Description", text: $detail)
            }
            .navigationTitle("Pick Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { dismiss(); onSave() }
                        .disabled(selectedClient == nil)
                }
            }
        }
    }
}
