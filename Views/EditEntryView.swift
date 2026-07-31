import SwiftUI
import SwiftData
import UIKit

struct EditEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Environment(\.appTheme) private var theme

    @Bindable var entry: Entry
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var selectedClient: Client?
    @State private var showDeleteAlert = false
    @State private var showUnsavedAlert = false
    @State private var showNewClient = false
    @State private var newClientName = ""
    @FocusState private var descFocused: Bool

    // Collapsed-by-default state for sections that start empty
    @State private var expensesExpanded = false
    @State private var notesExpanded = false

    // Communication local state (synced from entry)
    @State private var commChannel: String = "email"
    @State private var commDirection: String = "needsReply"
    @State private var commContact: String = ""
    @AppStorage("time.roundingIncrement") private var roundingRaw = "min15"

    // Focus newly-added subtask title
    @FocusState private var focusedSubtaskID: PersistentIdentifier?

    // Snapshot for change detection
    @State private var initialService = ""
    @State private var initialDetail = ""
    @State private var initialHours: Double = 0
    @State private var initialRate: Double = 0
    @State private var initialStatusRaw = ""
    @State private var initialNotes = ""
    @State private var initialIsImportant = false
    @State private var initialDueDate: Date? = nil
    @State private var initialBillOnCompletion = false
    @State private var initialServiceDate = Date()
    @State private var initialClient: Client? = nil

    private enum PickerClient: Hashable {
        case existing(Client?)
        case newClient
    }

    private var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    /// The task itself is the headline; fall back to the service name when
    /// there's no description yet (and skip the redundant service tag below
    /// it in that case, rather than showing "DESIGN" twice).
    private var headlineText: String {
        entry.detail.isEmpty ? entry.service : entry.detail
    }

    /// True once the entry has been deleted (locally, or by a CloudKit sync
    /// from another device). SwiftData traps on any property access to a
    /// deleted model, and SwiftUI re-evaluates this body at least once
    /// during the navigation pop that follows a delete — so the body has to
    /// tolerate the entry being gone rather than assume it's still there.
    private var entryIsGone: Bool {
        entry.isDeleted || entry.modelContext == nil
    }

    var body: some View {
        if entryIsGone {
            // Dismissal is already in flight; render nothing rather than
            // reading properties off a deleted model.
            Color.clear
        } else {
            formBody
        }
    }

    private var formBody: some View {
        Form {
            Section {
                summaryHeaderCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            detailsSection

            if entry.service == "COMM" {
                CommunicationDetailsSection(
                    channel: $commChannel,
                    direction: $commDirection,
                    contact: $commContact
                )
            }

            timeAndBillingSection
            expensesSection
            subtasksSection
            notesSection

            Section {
                Button {
                    syncCommFieldsToEntry()
                    entry.markModified()
                    try? ctx.save()
                    snapshotInitialState()
                    dismiss()
                } label: {
                    Label("Save Changes", systemImage: "tray.and.arrow.down.fill")
                }

                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Delete Entry", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Edit Entry")
        .alert("Delete Entry?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                // Pop first, then delete: starting the dismissal while the
                // view tree is still valid keeps the delete from racing the
                // navigation transition's body re-evaluation.
                dismiss()
                ctx.delete(entry)
                try? ctx.save()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the entry for \(entry.clientName) on \(DateFormatter.iso8601Day.string(from: entry.serviceDate)). This action can’t be undone.")
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if hasUnsavedChanges {
                        showUnsavedAlert = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            // Keyboard accessory
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedAlert) {
            Button("Save & Leave") {
                syncCommFieldsToEntry()
                entry.markModified()
                try? ctx.save()
                snapshotInitialState()
                dismiss()
            }
            Button("Discard", role: .destructive) {
                entry.service = initialService
                entry.detail = initialDetail
                entry.hours = initialHours
                entry.rate = initialRate
                entry.statusRaw = initialStatusRaw
                entry.notes = initialNotes
                entry.isImportant = initialIsImportant
                entry.dueDate = initialDueDate
                entry.billOnCompletion = initialBillOnCompletion
                entry.serviceDate = initialServiceDate
                entry.client = initialClient
                try? ctx.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Would you like to save before leaving?")
        }
        .onAppear {
            if selectedClient == nil { selectedClient = entry.client }
            // Load comm fields from entry
            commChannel = entry.commChannel ?? "email"
            commDirection = entry.commDirection ?? "needsReply"
            commContact = entry.commContact ?? ""
            expensesExpanded = entry.expenseAmount != 0 || entry.expenseMarkup != 0
            notesExpanded = !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            snapshotInitialState()
        }
        .onChange(of: entry.statusRaw) { _, _ in
            if entry.status == .done && entry.completedAt == nil {
                entry.completedAt = Date()
                try? ctx.save()
            }
        }
        .onChange(of: entry.service) { _, _ in entry.markModified() }
        .onChange(of: entry.serviceDate) { _, _ in entry.markModified() }
        .onChange(of: entry.detail) { _, _ in entry.markModified() }
        .onChange(of: entry.hours) { _, _ in entry.markModified() }
        .onChange(of: entry.rate) { _, _ in entry.markModified() }
        .onChange(of: entry.isImportant) { _, _ in entry.markModified() }
        .onChange(of: entry.billOnCompletion) { _, _ in entry.markModified() }
        .onChange(of: entry.timerStartedAt) { _, _ in entry.markModified() }
    }

    // MARK: - Summary header card

    private var summaryHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                // Order of importance: Task (the headline) → Service → Company.
                VStack(alignment: .leading, spacing: 4) {
                    Text(headlineText)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if !entry.detail.isEmpty && !entry.service.isEmpty {
                            Text(entry.service)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(theme.accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Text(entry.clientName)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        entry.isImportant.toggle()
                        entry.markModified()
                        try? ctx.save()
                    } label: {
                        Image(systemName: entry.isImportant ? "star.fill" : "star")
                            .foregroundStyle(entry.isImportant ? theme.overdue : theme.mutedText)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(entry.hours * entry.rate + entry.expenseTotal, format: .currency(code: currencyCode))
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(theme.primaryText)
                        Text("\(entry.hours, specifier: "%.1f")h · \(entry.rate, format: .currency(code: currencyCode))/hr")
                            .font(.caption2)
                            .foregroundStyle(theme.mutedText)
                    }
                }
            }

            Picker("Status", selection: statusBinding) {
                ForEach(EntryStatus.allCases, id: \.self) { s in
                    Text(s.displayLabel).tag(s)
                }
            }
            .pickerStyle(.segmented)

            if entry.status == .inProgress {
                TimerHeaderBlock(hours: $entry.hours, timerStartedAt: $entry.timerStartedAt) {
                    try? ctx.save()
                }
            } else if entry.status == .done {
                HStack {
                    Text("Completed")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    DatePicker("", selection: completedDateBinding, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
        .padding(16)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.divider, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusBinding: Binding<EntryStatus> {
        Binding(
            get: { entry.status },
            set: { entry.status = $0; entry.markModified() }
        )
    }

    private var completedDateBinding: Binding<Date> {
        Binding(
            get: { entry.completedAt ?? Date() },
            set: { newVal in
                entry.completedAt = newVal
                entry.markModified()
                try? ctx.save()
            }
        )
    }

    // MARK: - Details

    private var clientPickerBinding: Binding<PickerClient> {
        Binding(
            get: { .existing(selectedClient) },
            set: { newValue in
                switch newValue {
                case .newClient:
                    newClientName = ""
                    showNewClient = true
                case .existing(let c):
                    selectedClient = c
                    if let c {
                        entry.client = c
                        entry.rate = c.rate
                        entry.markModified()
                    }
                }
            }
        )
    }

    private var dueDateToggleBinding: Binding<Bool> {
        Binding(
            get: { entry.dueDate != nil },
            set: { on in
                entry.dueDate = on ? (entry.dueDate ?? Calendar.current.date(byAdding: .weekOfYear, value: 1, to: entry.serviceDate) ?? entry.serviceDate) : nil
                entry.markModified()
                try? ctx.save()
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { entry.dueDate ?? Date() },
            set: { entry.dueDate = $0; entry.markModified(); try? ctx.save() }
        )
    }

    private var detailsSection: some View {
        Section("Details") {
            Picker("Client", selection: clientPickerBinding) {
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
                Button("Add") { addNewClient() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enter the company name. It will be added to your clients list.")
            }

            Picker("Service", selection: $entry.service) {
                ForEach(Constants.services, id: \.self) { s in
                    Text(s).tag(s)
                }
            }

            DatePicker("Service Date", selection: $entry.serviceDate, displayedComponents: .date)

            Toggle("Due Date", isOn: dueDateToggleBinding)
            if entry.dueDate != nil {
                DatePicker("", selection: dueDateBinding, displayedComponents: .date)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                TextEditor(text: $entry.detail)
                    .frame(minHeight: descFocused ? 160 : 80, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.07))
                    )
                    .overlay(
                        Group {
                            if entry.detail.isEmpty {
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

    private func addNewClient() {
        let trimmed = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = clients.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            selectedClient = existing
            entry.client = existing
            entry.rate = existing.rate
            entry.markModified()
            return
        }
        let newClient = Client(name: trimmed, rate: entry.rate)
        ctx.insert(newClient)
        try? ctx.save()
        selectedClient = newClient
        entry.client = newClient
        entry.markModified()
    }

    // MARK: - Time & Billing

    private var timeLoggedSummary: String {
        let count = entry.timeLogsList.count
        return "\(String(format: "%.1f", entry.hours))h across \(count) \(count == 1 ? "entry" : "entries")"
    }

    private var timeAndBillingSection: some View {
        Section("Time & Billing") {
            HStack {
                Text("Rate")
                Spacer()
                TextField("Rate", value: $entry.rate, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }

            DisclosureGroup {
                // Filter before sorting: a deleted TimeLog can still be in
                // the relationship array for a beat (own delete swipe, entry
                // cascade delete, or a CloudKit delete from another device),
                // and reading .addedAt off one traps.
                let logs = entry.timeLogsList
                    .filter { !$0.isDeleted && $0.modelContext != nil }
                    .sorted { $0.addedAt > $1.addedAt }
                if logs.isEmpty {
                    Text("No time logged yet").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        timeLogRow(log)
                    }
                }
            } label: {
                HStack {
                    Text("Time Logged")
                    Spacer()
                    Text(timeLoggedSummary)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                TimeLogEditor(entry: entry) { hours, note in
                    let log = TimeLog(hours: hours, note: note, entry: entry)
                    entry.timeLogsList.append(log)
                    entry.hours += hours
                    entry.markModified()
                    try? ctx.save()
                }
            } label: {
                Label("Add Time…", systemImage: "plus.circle")
            }

            Toggle("Bill on Completion", isOn: $entry.billOnCompletion)
            if entry.billOnCompletion {
                Text("Invoice date will use the completion date instead of the service date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func timeLogRow(_ log: TimeLog) -> some View {
        DisclosureGroup {
            Stepper(value: Binding(
                get: { log.hours },
                set: { newVal in
                    let delta = newVal - log.hours
                    log.hours = newVal
                    entry.hours += delta
                    entry.markModified()
                    try? ctx.save()
                }
            ), in: 0.0...24, step: 0.25) {
                Text("\(log.hours, specifier: "%.2f")h")
                    .fontWeight(.semibold)
            }

            HStack {
                Text("Hours (edit)")
                Spacer()
                TextField("0.00", value: Binding(
                    get: { log.hours },
                    set: { newVal in
                        let clamped = max(0.0, min(24.0, newVal))
                        let rounded = applyRounding(clamped)
                        let delta = rounded - log.hours
                        log.hours = rounded
                        entry.hours += delta
                        entry.markModified()
                        try? ctx.save()
                    }
                ), format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            }

            TextField("Note", text: Binding(
                get: { log.note },
                set: { newVal in
                    log.note = newVal
                    entry.markModified()
                    try? ctx.save()
                }
            ))

            DatePicker("Date", selection: Binding(
                get: { log.addedAt },
                set: { newVal in
                    log.addedAt = newVal
                    entry.markModified()
                    try? ctx.save()
                }
            ), displayedComponents: [.date, .hourAndMinute])
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
                if let idx = entry.timeLogsList.firstIndex(where: { $0.persistentModelID == log.persistentModelID }) {
                    let doomed = entry.timeLogsList[idx]
                    entry.timeLogsList.remove(at: idx)
                    ctx.delete(doomed)
                    entry.markModified()
                    try? ctx.save()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Expenses (collapsed when empty)

    private var expensesSection: some View {
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
                    TextField("0.00", value: $entry.expenseAmount, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .onChange(of: entry.expenseAmount) { _, _ in entry.markModified(); try? ctx.save() }
                }
                HStack {
                    Text("Markup")
                    Spacer()
                    TextField("0", value: $entry.expenseMarkup, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                        .onChange(of: entry.expenseMarkup) { _, _ in entry.markModified(); try? ctx.save() }
                    Picker("", selection: $entry.expenseMarkupIsPercent) {
                        Text("%").tag(true)
                        Text("$").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 80)
                    .onChange(of: entry.expenseMarkupIsPercent) { _, _ in entry.markModified(); try? ctx.save() }
                }
                HStack {
                    Text("Expense Total")
                    Spacer()
                    Text(entry.expenseTotal, format: .currency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Subtasks (collapsed when empty)

    private var subtasksSection: some View {
        Section("Subtasks") {
            let items = entry.subtasksList.sorted { $0.createdAt < $1.createdAt }

            if items.isEmpty {
                Button {
                    addSubtask()
                } label: {
                    Label("+ Add Subtask…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(items) { st in
                    Toggle(isOn: Binding(
                        get: { st.isDone },
                        set: { newVal in
                            st.isDone = newVal
                            entry.markModified()
                            try? ctx.save()
                        }
                    )) {
                        TextField("Subtask name",
                                  text: Binding(
                                    get: { st.title },
                                    set: { newTitle in
                                        st.title = newTitle
                                        entry.markModified()
                                        try? ctx.save()
                                    }
                                  )
                        )
                        .focused($focusedSubtaskID, equals: st.persistentModelID)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteSubtask(st)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteSubtask(st)
                        } label: {
                            Label("Delete Subtask", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    for idx in offsets {
                        let st = items[idx]
                        deleteSubtask(st)
                    }
                }

                Button {
                    addSubtask()
                } label: {
                    Label("Add Subtask", systemImage: "plus.circle")
                }
            }
        }
    }

    private func addSubtask() {
        let new = Subtask(title: "", parent: entry)
        ctx.insert(new)
        entry.subtasksList.append(new)
        entry.markModified()
        try? ctx.save()
        focusedSubtaskID = new.persistentModelID
    }

    // MARK: - Notes (collapsed when empty)

    private var notesSection: some View {
        Section("Notes") {
            if !notesExpanded {
                Button {
                    withAnimation { notesExpanded = true }
                } label: {
                    Label("+ Add Notes…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add any context, decisions, or client requests…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $entry.notes)
                        .frame(minHeight: 120)
                        .onChange(of: entry.notes) { _, _ in
                            entry.markModified()
                            try? ctx.save()
                        }
                        .accessibilityLabel("Notes")
                }
                HStack {
                    Spacer()
                    Text("\(entry.notes.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

    private var hasUnsavedChanges: Bool {
        entry.service != initialService ||
        entry.detail != initialDetail ||
        entry.hours != initialHours ||
        entry.rate != initialRate ||
        entry.statusRaw != initialStatusRaw ||
        entry.notes != initialNotes ||
        entry.isImportant != initialIsImportant ||
        entry.dueDate != initialDueDate ||
        entry.billOnCompletion != initialBillOnCompletion ||
        entry.serviceDate != initialServiceDate ||
        entry.client != initialClient
    }

    private func snapshotInitialState() {
        initialService = entry.service
        initialDetail = entry.detail
        initialHours = entry.hours
        initialRate = entry.rate
        initialStatusRaw = entry.statusRaw
        initialNotes = entry.notes
        initialIsImportant = entry.isImportant
        initialDueDate = entry.dueDate
        initialBillOnCompletion = entry.billOnCompletion
        initialServiceDate = entry.serviceDate
        initialClient = entry.client
    }

    // MARK: - Helpers

    private func syncCommFieldsToEntry() {
        if entry.service == "COMM" {
            entry.commChannel = commChannel
            entry.commDirection = commDirection
            entry.commContact = commContact.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            entry.commChannel = nil
            entry.commDirection = nil
            entry.commContact = nil
        }
    }

    private func deleteSubtask(_ st: Subtask) {
        if let idx = entry.subtasksList.firstIndex(where: { $0.id == st.id }) {
            let doomed = entry.subtasksList[idx]
            ctx.delete(doomed)
            entry.markModified()
            try? ctx.save()
        }
    }
}

// MARK: - Timer Header Block (In Progress status)

private struct TimerHeaderBlock: View {
    @Binding var hours: Double
    @Binding var timerStartedAt: Date?
    var onChange: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var runningElapsedHours: Double {
        guard let start = timerStartedAt else { return 0 }
        let sec = Date().timeIntervalSince(start)
        return sec > 0 ? sec / 3600.0 : 0
    }

    private var runningElapsedText: String {
        let totalSeconds = Int(runningElapsedHours * 3600)
        let h = totalSeconds / 3600, m = (totalSeconds % 3600) / 60, s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var body: some View {
        VStack(spacing: 8) {
            if timerStartedAt == nil {
                Button {
                    timerStartedAt = Date()
                    onChange()
                } label: {
                    Label("Start Timer", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(theme.running).frame(width: 7, height: 7)
                        Text("Running")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.running)
                    }
                    Spacer()
                    Text(runningElapsedText)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.running)
                }
                .padding(9)
                .background(theme.runningLight)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack(spacing: 6) {
                    bumpButton("+15m") { bump(0.25) }
                    bumpButton("+30m") { bump(0.5) }
                    bumpButton("+1h") { bump(1.0) }
                    Button {
                        let add = runningElapsedHours
                        hours += add
                        timerStartedAt = nil
                        onChange()
                    } label: {
                        Text("Pause & Add")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .foregroundStyle(theme.success)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.success.opacity(0.35), lineWidth: 1))
                }
            }
        }
        .onReceive(timer) { _ in tick = Date() }
    }

    private func bump(_ h: Double) {
        hours += h
        onChange()
    }

    @ViewBuilder
    private func bumpButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .foregroundStyle(theme.running)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.running.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - TimeLogEditor (inline add)

private struct TimeLogEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: Entry
    let onSave: (Double, String) -> Void

    @State private var hours: Double = 0
    @State private var note: String = ""

    var body: some View {
        Form {
            Section("Add Time") {
                Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                    HStack { Text("Hours"); Spacer(); Text("\(hours, specifier: "%.2f")h").monospacedDigit().foregroundStyle(.secondary) }
                }
                TextField("Note (optional)", text: $note)
            }
            Section {
                Button {
                    guard hours > 0 else { dismiss(); return }
                    onSave(hours, note.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                } label: { Label("Save", systemImage: "tray.and.arrow.down.fill") }
            }
        }
        .navigationTitle("Add Time")
    }
}

// MARK: - Timer helper for Entry

extension Entry {
    /// Returns the number of elapsed hours since the timer was started, or nil if not running.
    var runningElapsedHours: Double? {
        guard let started = timerStartedAt else { return nil }
        return Date().timeIntervalSince(started) / 3600
    }
}
