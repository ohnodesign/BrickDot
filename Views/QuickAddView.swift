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
                        TextField("cs photo 121 Rasho Road", text: $rawInput)
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
                                .foregroundStyle(speech.isRecording ? .red : .accent)
                                .imageScale(.large)
                                .frame(width: 44, height: 44)
                        }
                    }

                    if speech.isRecording {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                                .font(.caption).foregroundStyle(.secondary)
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
                }

                // Parsed preview
                if let parsed = parsedPreview {
                    HStack(spacing: 8) {
                        Circle().fill(parsed.client.accentColor).frame(width: 10, height: 10)
                        Text(parsed.client.name).font(.subheadline.weight(.semibold))
                        Text(parsed.service).font(.caption).foregroundStyle(.secondary)
                        if !parsed.description.isEmpty {
                            Text("·").foregroundStyle(.secondary)
                            Text(parsed.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                } else if !rawInput.isEmpty && rawInput.contains(" ") {
                    Text("No match — try a different shortcode or use Pick Manually")
                        .font(.caption).foregroundStyle(.orange)
                }

                // Buttons row
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
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
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
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }

                // Quick Save button
                Button(action: save) {
                    HStack {
                        Image(systemName: "hare.fill")
                            .scaleEffect(0.8)
                        Text(isSaving ? "Saving…" : "Quick Save")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canSave ? Color(red: 0.75, green: 0.60, blue: 0.0) : Color(.systemGray4))
                    )
                    .foregroundStyle(.white)
                }
                .disabled(!canSave || isSaving)

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Add")
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
    }

    private func parseInput() {
        let words = rawInput.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard words.count >= 2 else { parsedPreview = nil; return }

        let clientQuery = String(words[0]).lowercased()
        let serviceQuery = String(words[1]).lowercased()
        let desc = words.count > 2 ? String(words[2]) : ""

        guard let matchedClient = matchClient(clientQuery) else { parsedPreview = nil; return }
        guard let matchedService = matchService(serviceQuery) else { parsedPreview = nil; return }

        parsedPreview = ParsedInput(client: matchedClient, service: matchedService, description: desc)
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
        Constants.services.first(where: { $0.lowercased().hasPrefix(query) })
    }

    // MARK: - Effective values

    private var effectiveClient: Client? { parsedPreview?.client ?? selectedClient }
    private var effectiveService: String { parsedPreview?.service ?? service }
    private var effectiveDetail: String {
        if let parsed = parsedPreview, !parsed.description.isEmpty { return parsed.description }
        return detail
    }
    private var canSave: Bool { effectiveClient != nil }

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
