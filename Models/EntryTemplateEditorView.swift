import SwiftUI
import SwiftData

struct EntryTemplateEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var template: EntryTemplate

    // Track if changes have been made
    @State private var hasChanges: Bool = false

    // Store original values to detect changes
    @State private var originalName: String = ""
    @State private var originalService: String = ""
    @State private var originalDetail: String = ""
    @State private var originalNotes: String = ""
    @State private var originalDefaultHours: Double = 0
    @State private var originalSubtaskCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $template.name)
                        .onChange(of: template.name) { _, _ in checkForChanges() }

                    Picker("Service", selection: $template.service) {
                        ForEach(Constants.services, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    .onChange(of: template.service) { _, _ in checkForChanges() }

                    TextField("Detail", text: $template.detail, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: template.detail) { _, _ in checkForChanges() }

                    TextField("Notes", text: $template.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .onChange(of: template.notes) { _, _ in checkForChanges() }

                    HStack {
                        Text("Default Hours")
                        Spacer()
                        TextField("0", value: $template.defaultHours, formatter: NumberFormatter.decimal)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            .onChange(of: template.defaultHours) { _, _ in checkForChanges() }
                    }
                }

                SubtasksSectionView(template: template)
                    .onChange(of: template.subtasks.count) { _, _ in checkForChanges() }
            }
            .navigationTitle("Entry Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save Template") {
                        saveTemplate()
                    }
                    .disabled(!hasChanges)
                    .fontWeight(hasChanges ? .semibold : .regular)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .onAppear {
                // Store original values on appear
                originalName = template.name
                originalService = template.service
                originalDetail = template.detail
                originalNotes = template.notes
                originalDefaultHours = template.defaultHours
                originalSubtaskCount = template.subtasks.count
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func checkForChanges() {
        hasChanges = template.name != originalName ||
                     template.service != originalService ||
                     template.detail != originalDetail ||
                     template.notes != originalNotes ||
                     template.defaultHours != originalDefaultHours ||
                     template.subtasks.count != originalSubtaskCount
    }

    private func saveTemplate() {
        try? modelContext.save()
        dismiss()
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
    ModelPreviewHost()
}

// Helper view for previews that sets up an in-memory container and seeds sample data.
private struct ModelPreviewHost: View {
    @Environment(\.modelContext) private var context
    @State private var didSeed = false

    @State private var template: EntryTemplate

    init() {
        // Create minimal sample graph
        let client = Client(name: "Acme Corp", rate: 0)
        let template = EntryTemplate(name: "Website Update", service: "WEBUP", client: client)
        template.subtasks = [
            TemplateSubtask(title: "Design review", order: 0, template: template),
            TemplateSubtask(title: "Implement changes", order: 1, template: template),
            TemplateSubtask(title: "QA & handoff", order: 2, template: template)
        ]
        _template = State(initialValue: template)
    }

    var body: some View {
        EntryTemplateEditorView(template: template)
            .modelContainer(for: [EntryTemplate.self, TemplateSubtask.self], inMemory: true)
            .onAppear {
                if !didSeed {
                    // Insert client and template into the in-memory context once
                    if template.client.modelContext == nil {
                        context.insert(template.client)
                    }
                    if template.modelContext == nil {
                        context.insert(template)
                    }
                    didSeed = true
                }
            }
    }
}

