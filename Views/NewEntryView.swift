import SwiftUI
import SwiftData
import UIKit

struct NewEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Query(sort: \Client.name) private var clients: [Client]

    // Local state for a new entry
    @State private var selectedClient: Client?
    @State private var service: String = (Constants.services.first ?? "")
    @State private var serviceDate: Date = .now
    @State private var detail: String = ""
    @State private var hours: Double = 0
    @State private var rate: Double = 0
    @State private var status: EntryStatus = .todo
    @State private var timerStartedAt: Date? = nil
    @State private var isImportant: Bool = false   // ✅ NEW

    // New: notes and pending subtasks for brand new entries
    @State private var notes: String = ""
    @State private var pendingSubtasks: [PendingSubtask] = []

    private struct PendingLog: Identifiable, Hashable {
        let id = UUID()
        var hours: Double
        var note: String
        var addedAt: Date = Date()
    }
    @State private var pendingLogs: [PendingLog] = []

    // Prevent duplicate taps
    @State private var isSaving = false

    // Force a full form rebuild when we reset (clears focus/child state)
    @State private var formResetKey = UUID()

    @AppStorage("time.roundingIncrement") private var roundingRaw = "min15"

    /// Optional hook the caller can use (e.g., to switch tabs after save)
    var onSaved: (() -> Void)? = nil

    var prefillClient: Client? = nil
    var prefillTemplate: EntryTemplate? = nil

    private struct PendingSubtask: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var isDone: Bool = false
    }

    var body: some View {
        Form {
            EntryFormSection(
                clients: clients,
                selectedClient: $selectedClient,
                service: $service,
                serviceDate: $serviceDate,
                detail: $detail,
                hours: $hours,
                rate: $rate,
                status: $status,
                timerStartedAt: $timerStartedAt,
                isImportant: $isImportant         // ✅ pass down
            )

            // Notes section (visible when creating a new entry)
            Section("Notes") {
                ZStack(alignment: .topLeading) {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add any context, decisions, or client requests…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Notes")
                }
                HStack {
                    Spacer()
                    Text("\(notes.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                // Show pending logs (most recent first)
                let logs = pendingLogs.sorted { $0.addedAt > $1.addedAt }
                if logs.isEmpty {
                    Text("No time logged yet").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        DisclosureGroup {
                            // Inline editor content
                            if let idx = pendingLogs.firstIndex(where: { $0.id == log.id }) {
                                Stepper(value: Binding(
                                    get: { pendingLogs[idx].hours },
                                    set: { newVal in
                                        let clamped = max(0.0, min(24.0, newVal))
                                        // Adjust total hours to reflect change
                                        let delta = clamped - pendingLogs[idx].hours
                                        pendingLogs[idx].hours = clamped
                                        hours += delta
                                    }
                                ), in: 0.0...24, step: 0.25) {
                                    Text("\(pendingLogs[idx].hours, specifier: "%.2f")h")
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }

                                HStack {
                                    Text("Hours (edit)")
                                    Spacer()
                                    TextField("0.00", value: Binding(
                                        get: { pendingLogs[idx].hours },
                                        set: { newVal in
                                            let clamped = max(0.0, min(24.0, newVal))
                                            let rounded = applyRounding(clamped)
                                            let delta = rounded - pendingLogs[idx].hours
                                            pendingLogs[idx].hours = rounded
                                            hours += delta
                                        }
                                    ), format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120)
                                }

                                TextField("Note", text: Binding(
                                    get: { pendingLogs[idx].note },
                                    set: { newVal in pendingLogs[idx].note = newVal }
                                ))

                                DatePicker("Date", selection: Binding(
                                    get: { pendingLogs[idx].addedAt },
                                    set: { newVal in pendingLogs[idx].addedAt = newVal }
                                ), displayedComponents: [.date, .hourAndMinute])
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(log.hours, specifier: "%.2f")h")
                                        .font(.subheadline).fontWeight(.semibold)
                                    if !log.note.isEmpty {
                                        Text(log.note)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(log.addedAt, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if let idx = pendingLogs.firstIndex(where: { $0.id == log.id }) {
                                    let doomed = pendingLogs[idx]
                                    pendingLogs.remove(at: idx)
                                    // Reduce total hours by removed log amount
                                    hours -= doomed.hours
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                HStack {
                    Text("Amount")
                    Spacer()
                    Text(hours * rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    NewTimeLogEditor(onSave: { addedHours, note in
                        // For new entries, just bump hours; notes can optionally be appended
                        hours += addedHours
                        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            if notes.isEmpty { notes = "Time: \(trimmed)" }
                            else { notes += "\nTime: \(trimmed)" }
                        }
                        pendingLogs.insert(PendingLog(hours: addedHours, note: note), at: 0)
                    })
                } label: {
                    Label("Add Time…", systemImage: "plus.circle")
                }
            } header: {
                Text("Time Log")
            }

            // Subtasks section (simple editor prior to saving the entry)
            Section {
                Button {
                    pendingSubtasks.append(PendingSubtask(title: ""))
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add New Subtask").fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 4)

                if pendingSubtasks.isEmpty {
                    Text("No subtasks yet").foregroundStyle(.secondary)
                } else {
                    ForEach($pendingSubtasks) { $st in
                        Toggle(isOn: $st.isDone) {
                            TextField("Subtask name", text: $st.title)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                if let idx = pendingSubtasks.firstIndex(where: { $0.id == st.id }) {
                                    pendingSubtasks.remove(at: idx)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if let idx = pendingSubtasks.firstIndex(where: { $0.id == st.id }) {
                                    pendingSubtasks.remove(at: idx)
                                }
                            } label: {
                                Label("Delete Subtask", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        pendingSubtasks.remove(atOffsets: offsets)
                    }
                }
            } header: {
                Text("Subtasks")
            }

            Section {
                Button(action: save) {
                    if isSaving {
                        HStack { ProgressView(); Text("Saving…") }
                    } else {
                        Label("Save Entry", systemImage: "tray.and.arrow.down.fill")
                    }
                }
                .disabled(!canSave || isSaving)
            }
        }
        .id(formResetKey) // rebuilds the Form when we reset
        .navigationTitle("New Entry")
        .toolbar {
            // Single shared keyboard accessory in the parent
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {          // ✅ clearer wording
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if let pre = prefillClient {
                selectedClient = pre
                rate = pre.rate
            } else {
                if selectedClient == nil { selectedClient = clients.first }
                if let c = selectedClient { rate = c.rate }
            }
            // Apply template if provided
            if let template = prefillTemplate {
                service = template.service
                detail = template.detail
                notes = template.notes
                if template.defaultHours > 0 {
                    hours = template.defaultHours
                }
            }
        }
        .onChange(of: selectedClient) { _, c in
            if let c { rate = c.rate }
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        selectedClient != nil &&
        !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard !isSaving, let client = selectedClient else { return }
        isSaving = true

        let entry = Entry(
            serviceDate: serviceDate,
            service: service,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            hours: hours,
            rate: rate,
            client: client,
            status: status,              // keep order: status before timerStartedAt
            timerStartedAt: timerStartedAt,
            createdAt: Date(),
            isImportant: isImportant     // ✅ persist it
        )
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        ctx.insert(entry)

        // Create TimeLog models from pending logs
        for log in pendingLogs {
            let model = TimeLog(hours: log.hours, note: log.note, entry: entry)
            entry.timeLogs.append(model)
        }

        // Create Subtask models from pending subtasks
        for st in pendingSubtasks where !st.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let model = Subtask(title: st.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                parent: entry,
                                hours: 0,
                                isDone: st.isDone)
            entry.subtasks.append(model)
        }

        do {
            try ctx.save()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isSaving = false

            // Clear the form so when you come back to the New tab it's fresh
            resetForm()

            onSaved?()        // e.g., switch tabs if shown in the New tab
            dismiss()         // closes if presented as a sheet
        } catch {
            isSaving = false  // re-enable button so user can retry
        }
    }

    private func resetForm() {
        selectedClient = clients.first
        service        = (Constants.services.first ?? "")
        serviceDate    = .now
        detail         = ""
        hours          = 0
        rate           = selectedClient?.rate ?? 0
        status         = .todo
        timerStartedAt = nil
        isImportant    = false
        notes = ""
        pendingSubtasks = []
        pendingLogs = []

        // Force full view refresh to drop any lingering focus/validation state
        formResetKey = UUID()
    }

    private func applyRounding(_ hours: Double) -> Double {
        let incrementMinutes: Double
        switch roundingRaw {
        case "min5": incrementMinutes = 5
        case "min10": incrementMinutes = 10
        default: incrementMinutes = 15
        }
        let minutes = hours * 60.0
        let roundedMinutes = (minutes / incrementMinutes).rounded() * incrementMinutes
        return max(0.0, min(24.0, roundedMinutes / 60.0))
    }
}

private struct NewTimeLogEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Double, String) -> Void

    @State private var hours: Double = 0
    @State private var note: String = ""

    var body: some View {
        Form {
            Section("Add Time") {
                Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                    HStack {
                        Text("Hours"); Spacer();
                        Text("\(hours, specifier: "%.2f")h").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                TextField("Note (optional)", text: $note)
            }
            Section {
                Button {
                    guard hours > 0 else { dismiss(); return }
                    onSave(hours, note)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down.fill")
                }
            }
        }
        .navigationTitle("Add Time")
    }
}

