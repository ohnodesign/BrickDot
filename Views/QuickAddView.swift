import SwiftUI
import SwiftData

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query(sort: \Client.name) private var clients: [Client]

    @State private var selectedClient: Client?
    @State private var service: String = Constants.services.first ?? ""
    @State private var detail: String = ""
    @State private var rawInput: String = ""
    @State private var isSaving = false
    @State private var showFullEntry = false
    @State private var useShorthand = false
    @State private var parsedPreview: ParsedInput?

    @StateObject private var speech = SpeechRecognizer()

    @AppStorage("quickadd.lastClientName") private var lastClientName = ""
    @AppStorage("quickadd.lastService") private var lastService = ""

    @FocusState private var inputFocused: Bool

    var prefillClient: Client? = nil
    var onSaved: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                // Shorthand input
                Section {
                    HStack {
                        TextField("cs photo 121 Rasho Road", text: $rawInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($inputFocused)
                            .onChange(of: rawInput) { _, _ in parseInput() }
                            .onSubmit { if parsedPreview != nil { save() } }

                        // Voice input button
                        Button {
                            if speech.isRecording {
                                speech.stopRecording()
                            } else {
                                Task {
                                    let ok = await speech.requestPermission()
                                    if ok {
                                        speech.transcript = ""
                                        speech.startRecording()
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                                .foregroundStyle(speech.isRecording ? .red : .accent)
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                    }

                    if speech.isRecording {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Use") {
                                rawInput = speech.transcript
                                speech.stopRecording()
                                parseInput()
                            }
                            .font(.caption.weight(.semibold))
                            .disabled(speech.transcript.isEmpty)
                        }
                    }

                    if let error = speech.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Quick Entry")
                } footer: {
                    Text("Format: **client service description** — e.g. \"cob photo 121 Rasho Road\"")
                }

                // Parsed preview / manual fallback
                if let parsed = parsedPreview {
                    Section("Parsed") {
                        HStack {
                            Circle().fill(parsed.client.accentColor).frame(width: 10, height: 10)
                            Text(parsed.client.name).fontWeight(.semibold)
                            Spacer()
                            Text(parsed.service)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !parsed.description.isEmpty {
                            Text(parsed.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if !rawInput.isEmpty {
                    Section {
                        Text("No match — use the pickers below or try a different prefix")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                // Manual pickers (fallback or override)
                Section("Or pick manually") {
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

                // Actions
                Section {
                    Button(action: save) {
                        if isSaving {
                            HStack { ProgressView(); Text("Saving…") }
                        } else {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text("Quick Save").fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .disabled(!canSave || isSaving)

                    Button {
                        showFullEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.pencil")
                            Text("More Details…")
                            Spacer()
                        }
                        .foregroundStyle(.accent)
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.stopRecording()
                        dismiss()
                    }
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
            .onDisappear {
                speech.stopRecording()
            }
            .sheet(isPresented: $showFullEntry) {
                NavigationStack {
                    NewEntryView(
                        onSaved: {
                            showFullEntry = false
                            onSaved?()
                            dismiss()
                        },
                        prefillClient: effectiveClient,
                        prefillService: effectiveService,
                        prefillDetail: effectiveDetail
                    )
                }
            }
        }
    }

    // MARK: - Shorthand Parser

    private struct ParsedInput {
        let client: Client
        let service: String
        let description: String
    }

    private func parseInput() {
        let words = rawInput.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard words.count >= 2 else { parsedPreview = nil; return }

        let clientQuery = String(words[0]).lowercased()
        let serviceQuery = String(words[1]).lowercased()
        let desc = words.count > 2 ? String(words[2]) : ""

        // Match client: prefix of name, or initials
        guard let matchedClient = matchClient(clientQuery) else {
            parsedPreview = nil
            return
        }

        // Match service: prefix match (case-insensitive)
        guard let matchedService = matchService(serviceQuery) else {
            parsedPreview = nil
            return
        }

        parsedPreview = ParsedInput(client: matchedClient, service: matchedService, description: desc)
    }

    private func matchClient(_ query: String) -> Client? {
        // 1. Exact prefix of client name
        if let match = clients.first(where: { $0.name.lowercased().hasPrefix(query) }) {
            return match
        }
        // 2. Match initials (first letter of each word)
        if let match = clients.first(where: {
            let initials = $0.name.split(separator: " ").compactMap({ $0.first }).map({ String($0).lowercased() }).joined()
            return initials.hasPrefix(query)
        }) {
            return match
        }
        // 3. Contains match as fallback
        if let match = clients.first(where: { $0.name.lowercased().contains(query) }) {
            return match
        }
        return nil
    }

    private func matchService(_ query: String) -> String? {
        // Exact prefix match
        if let match = Constants.services.first(where: { $0.lowercased().hasPrefix(query) }) {
            return match
        }
        return nil
    }

    // MARK: - Effective values (parsed overrides manual)

    private var effectiveClient: Client? {
        parsedPreview?.client ?? selectedClient
    }

    private var effectiveService: String {
        parsedPreview?.service ?? service
    }

    private var effectiveDetail: String {
        if let parsed = parsedPreview, !parsed.description.isEmpty {
            return parsed.description
        }
        return detail
    }

    private var canSave: Bool {
        effectiveClient != nil
    }

    private func save() {
        guard let client = effectiveClient, !isSaving else { return }
        isSaving = true

        let entry = Entry(
            serviceDate: Date(),
            service: effectiveService,
            detail: effectiveDetail.trimmingCharacters(in: .whitespacesAndNewlines),
            hours: 0,
            rate: client.rate,
            client: client,
            status: .todo,
            createdAt: Date(),
            isImportant: true
        )
        entry.isQuickAdd = true
        ctx.insert(entry)

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
