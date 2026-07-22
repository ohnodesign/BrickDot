import SwiftUI
import SwiftData

struct SubtasksSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var template: EntryTemplate

    @State private var newSubtaskTitle: String = ""

    var body: some View {
        Section(header: header) {
            ForEach(template.orderedSubtasks) { subtask in
                SubtaskRow(subtask: subtask,
                           onDelete: { deleteSubtask(subtask) },
                           onMoveUp: { moveSubtaskUp(subtask) },
                           onMoveDown: { moveSubtaskDown(subtask) })
            }
            .onMove(perform: moveSubtasks)
            .onDelete(perform: deleteSubtasks)

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
        .onChange(of: template.subtasksList.count) { _, _ in normalizeOrders() }
    }

    private var header: some View {
        HStack {
            Text("Subtasks")
            Spacer()
            if !template.subtasksList.isEmpty {
                Text("\(template.subtasksList.count)")
                    .foregroundStyle(.secondary)
                EditButton()
                    .font(.body)
                    .textCase(nil)
            }
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation {
            let order = (template.subtasksList.map(\.order).max() ?? -1) + 1
            let subtask = TemplateSubtask(title: title, isCompleted: false, order: order, template: template)
            template.subtasksList.append(subtask)
            newSubtaskTitle = ""
            try? modelContext.save()
        }
    }

    private func deleteSubtask(_ subtask: TemplateSubtask) {
        withAnimation {
            var items = template.orderedSubtasks
            guard let idx = items.firstIndex(where: { $0 === subtask }) else { return }
            items.remove(at: idx)
            modelContext.delete(subtask)
            renumber(items)
            try? modelContext.save()
        }
    }

    private func moveSubtaskUp(_ subtask: TemplateSubtask) {
        var items = template.orderedSubtasks
        guard let idx = items.firstIndex(where: { $0 === subtask }), idx > 0 else { return }
        withAnimation {
            items.swapAt(idx, idx - 1)
            renumber(items)
            try? modelContext.save()
        }
    }

    private func moveSubtaskDown(_ subtask: TemplateSubtask) {
        var items = template.orderedSubtasks
        guard let idx = items.firstIndex(where: { $0 === subtask }), idx < items.count - 1 else { return }
        withAnimation {
            items.swapAt(idx, idx + 1)
            renumber(items)
            try? modelContext.save()
        }
    }

    private func deleteSubtasks(at offsets: IndexSet) {
        withAnimation {
            var items = template.orderedSubtasks
            let doomed = offsets.map { items[$0] }
            items.remove(atOffsets: offsets)
            for item in doomed { modelContext.delete(item) }
            renumber(items)
            try? modelContext.save()
        }
    }

    private func moveSubtasks(from source: IndexSet, to destination: Int) {
        withAnimation {
            var items = template.orderedSubtasks
            items.move(fromOffsets: source, toOffset: destination)
            renumber(items)
            try? modelContext.save()
        }
    }

    /// Reassigns `order` to match the given display sequence (0-based, contiguous).
    private func renumber(_ items: [TemplateSubtask]) {
        for (idx, subtask) in items.enumerated() where subtask.order != idx {
            subtask.order = idx
        }
    }

    private func normalizeOrders() {
        renumber(template.orderedSubtasks)
    }
}

private struct SubtaskRow: View {
    @Bindable var subtask: TemplateSubtask
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
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
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onMoveUp) { Label("Move Up", systemImage: "arrow.up") }
            Button(action: onMoveDown) { Label("Move Down", systemImage: "arrow.down") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

#Preview {
    struct Host: View {
        @State private var template: EntryTemplate
        init() {
            let client = Client(name: "Acme", rate: 0)
            let t = EntryTemplate(name: "Demo", service: "WEBUP", client: client)
            t.subtasksList = [
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
