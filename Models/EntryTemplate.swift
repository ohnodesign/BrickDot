import Foundation
import SwiftData

@Model
final class TemplateSubtask {
    var title: String = ""
    var isCompleted: Bool = false
    var order: Int = 0

    @Relationship(inverse: \EntryTemplate.subtasks)
    var template: EntryTemplate?

    init(title: String = "", isCompleted: Bool = false, order: Int = 0, template: EntryTemplate? = nil) {
        self.title = title
        self.isCompleted = isCompleted
        self.order = order
        self.template = template
    }
}

@Model
final class EntryTemplate {
    var name: String = ""
    var service: String = ""
    var detail: String = ""
    var notes: String = ""
    var defaultHours: Double = 0
    var client: Client?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade)
    var subtasks: [TemplateSubtask]? = []

    var subtasksList: [TemplateSubtask] {
        get { subtasks ?? [] }
        set { subtasks = newValue }
    }

    init(
        name: String = "",
        service: String = "",
        detail: String = "",
        notes: String = "",
        defaultHours: Double = 0,
        client: Client? = nil,
        createdAt: Date = Date(),
        subtasks: [TemplateSubtask] = []
    ) {
        self.name = name
        self.service = service
        self.detail = detail
        self.notes = notes
        self.defaultHours = defaultHours
        self.client = client
        self.createdAt = createdAt
        self.subtasks = subtasks

        for subtask in self.subtasksList {
            if subtask.template == nil {
                subtask.template = self
            }
        }
    }
}
