import SwiftUI
import SwiftData
import UIKit

struct NewEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

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
    @State private var isImportant: Bool = false
    @State private var dueDate: Date? = nil
    @State private var showDueDatePicker: Bool = false
    @State private var billOnCompletion: Bool = false

    // New: notes and pending subtasks for brand new entries
    @State private var notes: String = ""
    @State private var expenseAmount: Double = 0
    @State private var expenseMarkup: Double = 0
    @State private var expenseMarkupIsPercent: Bool = true
    @State private var pendingSubtasks: [PendingSubtask] = []

    // Communication fields (COMM service type)
    @State private var commChannel: String = "email"
    @State private var commDirection: String = "needsReply"
    @State private var commContact: String = ""

    // Expenses collapsed by default (#8)
    @State private var expensesExpanded: Bool = false

    private struct PendingLog: Identifiable, Hashable {
        let id = UUID()
        var hours: Double
        var note: String
        var addedAt: Date = Date()
    }
    @State private var pendingLogs: [PendingLog] = []

    // Prevent duplicate taps
    @State private var isSaving = false
    @State private var showUnsavedAlert = false

    // Force a full form rebuild when we reset (clears focus/child state)
    @State private var formResetKey = UUID()

    @AppStorage("time.roundingIncrement") private var roundingRaw = "min15"

    /// Optional hook the caller can use (e.g., to switch tabs after save)
    var onSaved: (() -> Void)? = nil

    var prefillClient: Client? = nil
    var prefillTemplate: EntryTemplate? = nil
    var prefillService: String? = nil
    var prefillDetail: String? = nil

    private struct PendingSubtask: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var isDone: Bool = false
    }

    var body: some View {
        Form {
            // ── Project → Communication Details → Status (via EntryFormSection) ──
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
                isImportant: $isImportant,
                commChannel: $commChannel,
                commDirection: $commDirection,
                commContact: $commContact
            )

            // ── Deadline & Billing ──
            Section("Deadline & Billing") {
                // Rate with $/hr label (#6)
                HStack {
                    Text("Rate")
                    Spacer()
                    TextField("Rate", value: $rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                    Text("$/hr")
                        .foregroundStyle(.secondary)
                }
                Toggle("Set Due Date", isOn: Binding(
                    get: { showDueDatePicker },
                    set: { on in
                        showDueDatePicker = on
                        if on && dueDate == nil {
                            dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: serviceDate) ?? serviceDate
                        }
                        if !on { dueDate = nil }
                    }
                ))
                if showDueDatePicker, let _ = dueDate {
                    DatePicker("Due Date",
                               selection: Binding(
                                   get: { dueDate ?? serviceDate },
                                   set: { dueDate = $0 }
                               ),
                               displayedComponents: .date)
                }
                Toggle("Bill on Completion", isOn: $billOnCompletion)
                // Subtext for bill on completion (#7)
                if billOnCompletion {
                    Text("Invoice on completion date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Expenses (collapsed by default) (#8) ──
            Section("Expenses") {
                if !expensesExpanded {
                    Button {
                        withAnimation { expensesExpanded = true }
                    } label: {
                        Label("+ Add Expense…", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", value: $expenseAmount, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    HStack {
                        Text("Markup")
                        Spacer()
                        TextField("0", value: $expenseMarkup, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Picker("", selection: $expenseMarkupIsPercent) {
                            Text("%").tag(true)
                            Text("$").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 80)
                    }
                    HStack {
                        Text("Expense Total")
                        Spacer()
                        Text(computedExpenseTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ── Time Log ──
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
                                    hours -= doomed.hours
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                // Renamed "Amount" → "Total" (#9)
                HStack {
                    Text("Total")
                    Spacer()
                    Text(hours * rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    NewTimeLogEditor(onSave: { addedHours, note in
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

            // ── Subtasks ──
            Section {
                // Outline / plain style button (#10)
                Button {
                    pendingSubtasks.append(PendingSubtask(title: ""))
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add New Subtask")
                        Spacer()
                    }
                }
                .foregroundStyle(theme.accent)

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

            // ── Notes (moved after Subtasks) ──
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

            // ── Save — full-width primary button (#11) ──
            Section {
                Button(action: save) {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                            Text("Saving…")
                            Spacer()
                        }
                    } else {
                        HStack {
                            Spacer()
                            Label("Save Entry", systemImage: "tray.and.arrow.down.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
                .disabled(!canSave || isSaving)
                .listRowInsets(EdgeInsets())
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(canSave ? Color(red: 0.79, green: 0.25, blue: 0.25) : Color.gray.opacity(0.3))
                .foregroundStyle(.white)
            }
        }
        .id(formResetKey) // rebuilds the Form when we reset
        .navigationTitle("New Entry")
        .navigationBarTitleDisplayMode(.inline) // (#1) no duplicate large title
        .interactiveDismissDisabled(hasUnsavedChanges)
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save Entry") { save() }
                .disabled(!canSave)
            Button("Discard", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Would you like to save before leaving?")
        }
        .toolbar {
            // Single shared keyboard accessory in the parent
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel") {
                    if hasUnsavedChanges {
                        showUnsavedAlert = true
                    } else {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let pre = prefillClient.live {
                selectedClient = pre
                rate = pre.rate
            } else {
                if selectedClient.live == nil { selectedClient = clients.first }
                if let c = selectedClient.live { rate = c.rate }
            }
            // Apply Quick Add prefills
            if let s = prefillService { service = s }
            if let d = prefillDetail { detail = d }
            // Apply template if provided
            if let template = prefillTemplate {
                service = template.service
                detail = template.detail
                notes = template.notes
                if template.defaultHours > 0 {
                    hours = template.defaultHours
                }
                pendingSubtasks = template.subtasksList
                    .sorted { $0.order < $1.order }
                    .map { PendingSubtask(title: $0.title) }
            }
        }
        .onChange(of: selectedClient) { _, c in
            if let c { rate = c.rate }
        }
        .onChange(of: service) { _, newService in
            // Auto-set important for COMM entries (#6)
            if newService == "COMM" {
                isImportant = true
            }
        }
    }

    // MARK: - Helpers

    private var hasUnsavedChanges: Bool {
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        hours > 0 ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !pendingSubtasks.isEmpty ||
        !pendingLogs.isEmpty ||
        isImportant ||
        dueDate != nil ||
        billOnCompletion ||
        expenseAmount > 0 ||
        timerStartedAt != nil ||
        status != .todo
    }

    private var computedExpenseTotal: Double {
        if expenseMarkupIsPercent {
            return expenseAmount * (1 + expenseMarkup / 100)
        } else {
            return expenseAmount + expenseMarkup
        }
    }

    private var canSave: Bool {
        selectedClient.live != nil &&
        !service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard !isSaving, let client = selectedClient.live else { return }
        isSaving = true

        let entry = Entry(
            serviceDate: serviceDate,
            service: service,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            hours: hours,
            rate: rate,
            client: client,
            status: status,
            timerStartedAt: timerStartedAt,
            createdAt: Date(),
            isImportant: isImportant,
            dueDate: showDueDatePicker ? dueDate : nil,
            billOnCompletion: billOnCompletion
        )
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.expenseAmount = expenseAmount
        entry.expenseMarkup = expenseMarkup
        entry.expenseMarkupIsPercent = expenseMarkupIsPercent

        // Communication fields
        if service == "COMM" {
            entry.commChannel = commChannel
            entry.commDirection = commDirection
            entry.commContact = commContact.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        ctx.insert(entry)

        // Create TimeLog models from pending logs
        for log in pendingLogs {
            let model = TimeLog(hours: log.hours, note: log.note, entry: entry)
            entry.timeLogsList.append(model)
        }

        // Create Subtask models from pending subtasks
        for st in pendingSubtasks where !st.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let model = Subtask(title: st.title.trimmingCharacters(in: .whitespacesAndNewlines),
                                parent: entry,
                                hours: 0,
                                isDone: st.isDone)
            ctx.insert(model)
            entry.subtasksList.append(model)
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
        rate           = selectedClient.live?.rate ?? 0
        status         = .todo
        timerStartedAt = nil
        isImportant    = false
        dueDate        = nil
        showDueDatePicker = false
        billOnCompletion = false
        notes = ""
        expenseAmount = 0
        expenseMarkup = 0
        expenseMarkupIsPercent = true
        pendingSubtasks = []
        pendingLogs = []
        expensesExpanded = false
        commChannel = "email"
        commDirection = "needsReply"
        commContact = ""

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
