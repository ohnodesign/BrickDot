import SwiftUI
import SwiftData

struct SubtasksSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: EntryTemplate

    @State private var newSubtaskTitle: String = ""

    var body: some View {
        Section(header: header) {
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
        .onChange(of: template.subtasks) { _ in normalizeOrders() }
    }

    private var header: some View {
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
        let order = (template.subtasks.map(\.order).max() ?? -1) + 1
        let subtask = TemplateSubtask(title: title, isCompleted: false, order: order, template: template)
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

#Preview {
    // Preview host for the section only
    struct Host: View {
        @State private var template: EntryTemplate
        init() {
            let client = Client(name: "Acme", rate: 0)
            let t = EntryTemplate(name: "Demo", service: "Service", client: client)
            t.subtasks = [
                TemplateSubtask(title: "One", order: 0, template: t),
                TemplateSubtask(title: "Two", order: 1, template: t)
            ]
            _template = State(initialValue: t)
        }
        var body: some View {
            Form {
                SubtasksSectionView(template: template)
            }
            .modelContainer(for: [EntryTemplate.self, TemplateSubtask.self], inMemory: true)
        }
    }
    return Host()
}
