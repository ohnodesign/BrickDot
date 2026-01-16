import SwiftUI
import SwiftData
import UIKit

struct EditEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @Bindable var entry: Entry
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var selectedClient: Client?
    @State private var showDeleteAlert = false
    @AppStorage("time.roundingIncrement") private var roundingRaw = "min15"

    // Focus newly-added subtask title
    @FocusState private var focusedSubtaskID: PersistentIdentifier?

    var body: some View {
        Form {
            // MARK: Core Entry fields
            EntryFormSection(
                clients: clients,
                selectedClient: Binding(
                    get: { selectedClient ?? entry.client },
                    set: { newVal in
                        selectedClient = newVal
                        if let c = newVal {
                            entry.client = c
                            entry.rate = c.rate
                        }
                    }
                ),
                service: $entry.service,
                serviceDate: $entry.serviceDate,
                detail: $entry.detail,
                hours: $entry.hours,
                rate: $entry.rate,
                status: $entry.status,
                timerStartedAt: $entry.timerStartedAt,
                isImportant: $entry.isImportant,
                onProgressStart: { try? ctx.save() },
                onProgressPauseAndAdd: { _ in try? ctx.save() },
                onProgressMarkDone: { 
                    if entry.completedAt == nil { 
                        entry.completedAt = Date() 
                    }
                    try? ctx.save() 
                }
            )

            // MARK: Dates
            Section("Dates") {
                HStack {
                    Text("Service Date")
                    Spacer()
                    DatePicker("", selection: $entry.serviceDate, displayedComponents: .date)
                        .labelsHidden()
                }
                HStack {
                    Text("Completed Date")
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { entry.completedAt ?? Date() },
                        set: { newVal in
                            entry.completedAt = newVal
                            try? ctx.save()
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .disabled(entry.status != .done)
                    .opacity(entry.status == .done ? 1.0 : 0.5)
                }
                if entry.status != .done {
                    Text("Set status to Done to edit Completed Date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Notes (NEW)
            Section("Notes") {
                ZStack(alignment: .topLeading) {
                    // Placeholder
                    if entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add any context, decisions, or client requests…")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $entry.notes)
                        .frame(minHeight: 120)
                        .onChange(of: entry.notes) { _, _ in try? ctx.save() }
                        .accessibilityLabel("Notes")
                }
                HStack {
                    Spacer()
                    Text("\(entry.notes.count) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Time Log
            Section {
                // Existing logs (most recent first)
                let logs = entry.timeLogs.sorted { $0.addedAt > $1.addedAt }
                if logs.isEmpty {
                    Text("No time logged yet").foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        DisclosureGroup {
                            // Inline editor content
                            Stepper(value: Binding(
                                get: { log.hours },
                                set: { newVal in
                                    let delta = newVal - log.hours
                                    log.hours = newVal
                                    entry.hours += delta
                                    try? ctx.save()
                                }
                            ), in: 0.0...24, step: 0.25) {
                                Text("\(log.hours, specifier: "%.2f")h")
                                    .fontWeight(.semibold)
                            }
                            
                            // Inline editor: Direct numeric entry for hours
                            HStack {
                                Text("Hours (edit)")
                                Spacer()
                                TextField("0.00", value: Binding(
                                    get: { log.hours },
                                    set: { newVal in
                                        // Clamp and round based on settings
                                        let clamped = max(0.0, min(24.0, newVal))
                                        let rounded = applyRounding(clamped)
                                        let delta = rounded - log.hours
                                        log.hours = rounded
                                        entry.hours += delta
                                        try? ctx.save()
                                    }
                                ), format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 120)
                            }
                            
                            // Inline editor: Note
                            TextField("Note", text: Binding(
                                get: { log.note },
                                set: { newVal in
                                    log.note = newVal
                                    try? ctx.save()
                                }
                            ))
                            
                            DatePicker("Date", selection: Binding(
                                get: { log.addedAt },
                                set: { newVal in
                                    log.addedAt = newVal
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
                                if let idx = entry.timeLogs.firstIndex(where: { $0.persistentModelID == log.persistentModelID }) {
                                    let doomed = entry.timeLogs[idx]
                                    entry.timeLogs.remove(at: idx)
                                    ctx.delete(doomed)
                                    try? ctx.save()
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
                    Text(entry.hours * entry.rate, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Add new log
                NavigationLink {
                    TimeLogEditor(entry: entry) { hours, note in
                        let log = TimeLog(hours: hours, note: note, entry: entry)
                        entry.timeLogs.append(log)
                        entry.hours += hours
                        try? ctx.save()
                    }
                } label: {
                    Label("Add Time…", systemImage: "plus.circle")
                }
            } header: {
                Text("Time Log")
            }

            // MARK: Subtasks (simple: title + checkbox, swipe to delete)
            Section {
                // Add new subtask
                Button {
                    let new = Subtask(title: "", parent: entry)
                    entry.subtasks.append(new)
                    try? ctx.save()
                    focusedSubtaskID = new.persistentModelID
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

                let items = entry.subtasks.sorted { $0.createdAt < $1.createdAt }

                if items.isEmpty {
                    Text("No subtasks yet").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { st in
                        Toggle(isOn: Binding(
                            get: { st.isDone },
                            set: { newVal in
                                st.isDone = newVal
                                try? ctx.save()
                            }
                        )) {
                            TextField("Subtask name",
                                      text: Binding(
                                        get: { st.title },
                                        set: { newTitle in
                                            st.title = newTitle
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
                }
            } header: {
                Text("Subtasks")
            }

            // MARK: Save / Delete
            Section {
                Button {
                    try? ctx.save()
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
                ctx.delete(entry)
                try? ctx.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the entry for \(entry.client.name) on \(DateFormatter.iso8601Day.string(from: entry.serviceDate)). This action can’t be undone.")
        }
        .toolbar {
            // Keyboard accessory
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
            // Enable Edit mode for drag-delete UI if you want
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .onAppear {
            if selectedClient == nil { selectedClient = entry.client }
        }
        .onChange(of: entry.status) { _, newStatus in
            if newStatus == .done && entry.completedAt == nil {
                entry.completedAt = Date()
                try? ctx.save()
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

    // MARK: - Helpers
    private func deleteSubtask(_ st: Subtask) {
        if let idx = entry.subtasks.firstIndex(where: { $0.id == st.id }) {
            let doomed = entry.subtasks[idx]
            ctx.delete(doomed)
            try? ctx.save()
        }
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

