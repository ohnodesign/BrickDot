import SwiftUI
import SwiftData

struct EntryFormSection: View {
    // Data source
    let clients: [Client]

    // Bindings supplied by parent
    @Binding var selectedClient: Client?
    @Binding var service: String
    @Binding var serviceDate: Date
    @Binding var detail: String
    @Binding var hours: Double
    @Binding var rate: Double
    @Binding var status: EntryStatus
    @Binding var timerStartedAt: Date?
    @Binding var isImportant: Bool

    // Communication fields (shown when service == "COMM")
    @Binding var commChannel: String
    @Binding var commDirection: String
    @Binding var commContact: String

    // Optional callbacks
    var onProgressStart: (() -> Void)?
    var onProgressPauseAndAdd: ((_ addHours: Double) -> Void?)?
    var onProgressMarkDone: (() -> Void)?

    var body: some View {
        Group {
            ProjectSection(
                clients: clients,
                selectedClient: $selectedClient,
                service: $service,
                serviceDate: $serviceDate,
                detail: $detail,
                hours: $hours,
                rate: $rate
            )

            // Communication Details (only when COMM is selected)
            if service == "COMM" {
                CommunicationDetailsSection(
                    channel: $commChannel,
                    direction: $commDirection,
                    contact: $commContact
                )
            }

            StatusSection(
                status: $status,
                timerStartedAt: $timerStartedAt,
                isImportant: $isImportant
            )

            if status == .inProgress {
                ProgressSection(
                    hours: $hours,
                    timerStartedAt: $timerStartedAt,
                    onStart: { onProgressStart?() },
                    onPauseAndAdd: { add in _ = onProgressPauseAndAdd?(add) },
                    onMarkDone: {
                        status = .done
                        onProgressMarkDone?()
                    }
                )
            }
        }
        // Note: no toolbar here — parent view adds ONE shared keyboard toolbar.
    }
}

// MARK: - Status

private struct StatusSection: View {
    @Binding var status: EntryStatus
    @Binding var timerStartedAt: Date?
    @Binding var isImportant: Bool

    private var starColor: Color {
        switch status {
        case .todo:       return .orange
        case .inProgress: return .red
        case .done:       return .green
        }
    }

    var body: some View {
        Section("Status") {
            Picker("Status", selection: $status) {
                ForEach(EntryStatus.allCases, id: \.self) { s in
                    Text(s.displayLabel).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: status) { _, newStatus in
                if newStatus != .inProgress { timerStartedAt = nil }
            }

            Toggle(isOn: $isImportant) {
                HStack(spacing: 8) {
                    Image(systemName: isImportant ? "star.fill" : "star")
                        .foregroundStyle(starColor)
                    Text("Mark as Important")
                }
            }
        }
    }
}

// MARK: - Project (was CoreDetails)

private struct ProjectSection: View {
    let clients: [Client]

    @Binding var selectedClient: Client?
    @Binding var service: String
    @Binding var serviceDate: Date
    @Binding var detail: String
    @Binding var hours: Double
    @Binding var rate: Double

    @Environment(\.modelContext) private var ctx

    @FocusState private var descFocused: Bool
    @State private var showNewClient = false
    @State private var newClientName = ""

    private enum PickerClient: Hashable {
        case existing(Client?)
        case newClient
    }

    // Derived directly from selectedClient so the picker always shows the
    // assigned client on first render (a mirrored @State synced in onAppear
    // showed "+ New Client…" on Mac Catalyst). Choosing "＋ New Client…"
    // only opens the alert; the selection stays on the current client.
    private var pickerClient: Binding<PickerClient> {
        Binding(
            get: { .existing(selectedClient) },
            set: { newValue in
                switch newValue {
                case .newClient:
                    newClientName = ""
                    showNewClient = true
                case .existing(let c):
                    selectedClient = c
                    if let c { rate = c.rate }
                }
            }
        )
    }

    var body: some View {
        Section("Project") {
            // Client
            Picker("Client", selection: pickerClient) {
                if selectedClient == nil {
                    Text("Select Client…").tag(PickerClient.existing(nil))
                }
                Text("＋ New Client…").tag(PickerClient.newClient)
                ForEach(clients, id: \.persistentModelID) { c in
                    Text(c.name).tag(PickerClient.existing(c))
                }
            }
            .alert("New Client", isPresented: $showNewClient) {
                TextField("Company name", text: $newClientName)
                    .textInputAutocapitalization(.words)
                Button("Add") {
                    let trimmed = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if clients.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        if let existing = clients.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                            selectedClient = existing
                        }
                        return
                    }
                    let newClient = Client(name: trimmed, rate: rate)
                    ctx.insert(newClient)
                    try? ctx.save()
                    selectedClient = newClient
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter the company name. It will be added to your clients list.")
            }
            // Service
            Picker("Service", selection: $service) {
                ForEach(Constants.services, id: \.self) { s in
                    Text(s).tag(s)
                }
            }

            // Date
            DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)

            // Description — always visible, no collapse toggle
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")

                TextEditor(text: $detail)
                    .frame(minHeight: descFocused ? 160 : 80, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        Group {
                            if detail.isEmpty {
                                Text("Add a short description…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )
                    .focused($descFocused)
            }
            .animation(.easeInOut(duration: 0.2), value: descFocused)
        }
    }
}

// MARK: - Communication Details

struct CommunicationDetailsSection: View {
    @Binding var channel: String
    @Binding var direction: String
    @Binding var contact: String

    private let channels = ["email", "phone", "text", "chat"]
    private let channelLabels = ["Email", "Phone", "Text", "Chat"]
    private let directions = ["needsReply", "awaitingResponse"]
    private let directionLabels = ["Needs Reply", "Awaiting Response"]

    var body: some View {
        Section("Communication Details") {
            // Channel
            VStack(alignment: .leading, spacing: 6) {
                Text("Channel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Channel", selection: $channel) {
                    ForEach(Array(zip(channels, channelLabels)), id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Direction
            VStack(alignment: .leading, spacing: 6) {
                Text("Direction")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Direction", selection: $direction) {
                    ForEach(Array(zip(directions, directionLabels)), id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Contact
            HStack {
                Text("Contact")
                Spacer()
                TextField("Name or number…", text: $contact)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Progress (In-Progress only)

private struct ProgressSection: View {
    @Binding var hours: Double
    @Binding var timerStartedAt: Date?

    var onStart: () -> Void
    var onPauseAndAdd: (_ addHours: Double) -> Void
    var onMarkDone: () -> Void

    @State private var tick: Date = .init()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var runningElapsedHours: Double {
        guard let start = timerStartedAt else { return 0 }
        let sec = Date().timeIntervalSince(start)
        return sec > 0 ? sec / 3600.0 : 0
    }

    private var runningElapsedText: String {
        formatHours(runningElapsedHours)
    }

    var body: some View {
        Section("Progress") {
            if timerStartedAt == nil {
                Button {
                    timerStartedAt = Date()
                    onStart()
                } label: {
                    Label("Start Timer", systemImage: "play.circle.fill")
                }
            } else {
                HStack {
                    Text("Running")
                    Spacer()
                    Text(runningElapsedText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button {
                    let add = runningElapsedHours
                    hours += add
                    timerStartedAt = nil
                    onPauseAndAdd(add)
                } label: {
                    Label("Pause & Add \(runningElapsedText)", systemImage: "pause.circle.fill")
                }
            }

            HStack(spacing: 12) {
                Button { bumpHours(0.25) } label: { Text("+15m") }
                Button { bumpHours(0.5) }  label: { Text("+30m") }
                Button { bumpHours(1.0) }  label: { Text("+1h") }
                Spacer()
                Button(role: .destructive) {
                    timerStartedAt = nil
                    onMarkDone()
                } label: { Text("Mark Done") }
            }
        }
        .onReceive(timer) { _ in tick = Date() }
    }

    private func bumpHours(_ h: Double) { hours += h }

    private func formatHours(_ h: Double) -> String {
        let totalMinutes = Int((h * 60).rounded())
        let hr = totalMinutes / 60
        let mn = totalMinutes % 60
        return hr > 0 ? "\(hr)h \(mn)m" : "\(mn)m"
    }
}
