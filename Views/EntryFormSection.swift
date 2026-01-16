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
    @Binding var isImportant: Bool   // keeps your “important” flag

    // Optional callbacks
    var onProgressStart: (() -> Void)?
    var onProgressPauseAndAdd: ((_ addHours: Double) -> Void?)?
    var onProgressMarkDone: (() -> Void)?

    var body: some View {
        Group {
            StatusSection(
                status: $status,
                timerStartedAt: $timerStartedAt,
                isImportant: $isImportant
            )

            CoreDetailsSection(
                clients: clients,
                selectedClient: $selectedClient,
                service: $service,
                serviceDate: $serviceDate,
                detail: $detail,
                hours: $hours,
                rate: $rate
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
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: status) { _, newStatus in
                if newStatus != .inProgress { timerStartedAt = nil }
                if newStatus == .done {
                    // The parent should set completedAt when saving; this is a hint path
                }
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

// MARK: - Core Details

private struct CoreDetailsSection: View {
    let clients: [Client]

    @Binding var selectedClient: Client?
    @Binding var service: String
    @Binding var serviceDate: Date
    @Binding var detail: String
    @Binding var hours: Double
    @Binding var rate: Double

    // Focus & expand handling
    @FocusState private var focusedField: Field?
    @State private var descExpanded = false
    @FocusState private var descFocused: Bool

    private enum Field { case rate }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }
    private var hoursText: String { String(format: "%.2f", hours) }
    private var amountText: String { currencyString(hours * rate) }

    private func currencyString(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = currencyCode
        return nf.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    // Target height for the description editor
    private var descHeight: CGFloat { (descExpanded || descFocused) ? 180 : 96 }

    var body: some View {
        Section {
            // Client
            Picker("Client", selection: $selectedClient) {
                ForEach(clients, id: \.persistentModelID) { c in
                    Text(c.name).tag(Optional(c))
                }
            }
            .onChange(of: selectedClient) { _, c in
                if let c { rate = c.rate }
            }

            // Service
            Picker("Service", selection: $service) {
                ForEach(Constants.services, id: \.self) { s in
                    Text(s).tag(s)
                }
            }

            // Date
            DatePicker("Service Date", selection: $serviceDate, displayedComponents: .date)

            // Description (auto-expands on focus, can be toggled with a chevron)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description")
                    Spacer()
                    Button {
                        withAnimation(.easeInOut) { descExpanded.toggle() }
                    } label: {
                        Label(descExpanded ? "Collapse" : "Expand", systemImage: descExpanded ? "chevron.up" : "chevron.down")
                            .labelStyle(.iconOnly)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $detail)
                    .frame(minHeight: descHeight, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        // Placeholder
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
                    .onTapGesture {
                        // Tapping inside also expands for comfort
                        withAnimation(.easeInOut) { descExpanded = true }
                    }
                    .onChange(of: descFocused) { _, isFocused in
                        // Smoothly grow/shrink on focus changes
                        withAnimation(.easeInOut(duration: 0.2)) { _ = isFocused }
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: descExpanded)
            .animation(.easeInOut(duration: 0.2), value: descFocused)

            // Rate
            HStack {
                Text("Rate")
                Spacer()
                TextField("Rate", value: $rate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
                    .focused($focusedField, equals: .rate)
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

