import SwiftUI
import SwiftData

struct SubtasksSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: EntryTemplate

    @State private var newSubtaskTitle: String = ""

    var body: some View {
        Section(header: header) {
            // Subtasks list - expands as items are added
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
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteSubtask(subtask)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        moveSubtaskUp(subtask)
                    } label: { Label("Move Up", systemImage: "arrow.up") }
                    Button {
                        moveSubtaskDown(subtask)
                    } label: { Label("Move Down", systemImage: "arrow.down") }
                    Divider()
                    Button(role: .destructive) {
                        deleteSubtask(subtask)
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .onMove(perform: moveSubtasks)
            .onDelete(perform: deleteSubtasks)

            // Add new subtask row
            HStack {
                TextField("New subtask", text: $newSubtaskTitle)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.vertical, 4)
        }
        .onChange(of: template.subtasks) { _, _ in normalizeOrders() }
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
        withAnimation {
            let order = (template.subtasks.map(\.order).max() ?? -1) + 1
            let subtask = TemplateSubtask(title: title, isCompleted: false, order: order, template: template)
            template.subtasks.append(subtask)
            newSubtaskTitle = ""
            try? modelContext.save()
        }
    }

    private func deleteSubtask(_ subtask: TemplateSubtask) {
        withAnimation {
            if let idx = template.subtasks.firstIndex(where: { $0 === subtask }) {
                let doomed = template.subtasks[idx]
                modelContext.delete(doomed)
                template.subtasks.remove(at: idx)
                normalizeOrders()
                try? modelContext.save()
            }
        }
    }

    private func moveSubtaskUp(_ subtask: TemplateSubtask) {
        if let idx = template.subtasks.firstIndex(where: { $0 === subtask }), idx > 0 {
            withAnimation {
                template.subtasks.move(fromOffsets: IndexSet(integer: idx), toOffset: idx - 1)
                normalizeOrders()
                try? modelContext.save()
            }
        }
    }

    private func moveSubtaskDown(_ subtask: TemplateSubtask) {
        if let idx = template.subtasks.firstIndex(where: { $0 === subtask }), idx < template.subtasks.count - 1 {
            withAnimation {
                template.subtasks.move(fromOffsets: IndexSet(integer: idx), toOffset: idx + 2)
                normalizeOrders()
                try? modelContext.save()
            }
        }
    }

    private func deleteSubtasks(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let item = template.subtasks[index]
                modelContext.delete(item)
            }
            template.subtasks.remove(atOffsets: offsets)
            normalizeOrders()
            try? modelContext.save()
        }
    }

    private func moveSubtasks(from source: IndexSet, to destination: Int) {
        withAnimation {
            template.subtasks.move(fromOffsets: source, toOffset: destination)
            normalizeOrders()
            try? modelContext.save()
        }
    }

    private func normalizeOrders() {
        for (idx, subtask) in template.subtasks.enumerated() {
            if subtask.order != idx { subtask.order = idx }
        }
    }
}

#Preview {
    struct Host: View {
        @State private var template: EntryTemplate
        init() {
            let client = Client(name: "Acme", rate: 0)
            let t = EntryTemplate(name: "Demo", service: "WEBUP", client: client)
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

