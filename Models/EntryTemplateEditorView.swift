import SwiftUI
import SwiftData

struct EntryTemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: EntryTemplate

    @State private var newSubtaskTitle: String = ""

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $template.name)
                TextField("Service", text: $template.service)
                TextField("Detail", text: $template.detail, axis: .vertical)
                TextField("Notes", text: $template.notes, axis: .vertical)
                HStack {
                    Text("Default Hours")
                    Spacer()
                    TextField("0", value: $template.defaultHours, formatter: NumberFormatter.decimal)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }

            Section(header: subtaskHeader) {
                if template.subtasks.isEmpty {
                    Text("No subtasks yet").foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach($template.subtasks) { $subtask in
                            HStack {
                                Button(action: { subtask.isCompleted.toggle() }) {
                                    Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                TextField("Subtask title", text: $subtask.title)

                                Spacer()

                                // Optional drag handle visual
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .onDelete(perform: deleteSubtasks)
                        .onMove(perform: moveSubtasks)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 44)
                }

                HStack {
                    TextField("New subtask", text: $newSubtaskTitle)
                        .onSubmit(addSubtask)
                    Button(action: addSubtask) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Entry Template")
        .toolbar { EditButton() }
        .onChange(of: template.subtasks) { _ in
            normalizeOrders()
        }
    }

    private var subtaskHeader: some View {
        HStack {
            Text("Subtasks")
            Spacer()
            if !template.subtasks.isEmpty {
                Text("\(template.subtasks.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let order = (template.subtasks.map(\ .order).max() ?? -1) + 1
        let subtask = Subtask(title: title, isCompleted: false, order: order, template: template)
        template.subtasks.append(subtask)
        newSubtaskTitle = ""
        try? modelContext.save()
    }

    private func deleteSubtasks(at offsets: IndexSet) {
        for index in offsets {
            let item = template.subtasks[index]
            modelContext.delete(item)
        }
        template.subtasks.remove(atOffsets: offsets)
        normalizeOrders()
        try? modelContext.save()
    }

    private func moveSubtasks(from source: IndexSet, to destination: Int) {
        template.subtasks.move(fromOffsets: source, toOffset: destination)
        normalizeOrders()
        try? modelContext.save()
    }

    private func normalizeOrders() {
        for (idx, subtask) in template.subtasks.enumerated() {
            if subtask.order != idx { subtask.order = idx }
        }
    }
}

private extension NumberFormatter {
    static var decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()
}

#Preview {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: EntryTemplate.self, Subtask.self, configurations: config)
        let context = container.mainContext

        let client = Client(name: "Acme Corp")
        context.insert(client)

        let template = EntryTemplate(name: "Website Update", service: "Development", client: client)
        template.subtasks = [
            Subtask(title: "Design review", order: 0, template: template),
            Subtask(title: "Implement changes", order: 1, template: template),
            Subtask(title: "QA & handoff", order: 2, template: template)
        ]
        context.insert(template)

        return NavigationStack {
            EntryTemplateEditorView(template: template)
        }
        .modelContainer(container)
    } catch {
        return Text("Preview Error: \(String(describing: error))")
    }
}
