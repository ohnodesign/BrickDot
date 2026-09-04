import Foundation
import Observation
import SwiftData

/// The Coach conversation, owned above the tab bar so it outlives the view.
///
/// This used to be `@State` on `CoachView`. SwiftUI destroys that view whenever
/// you leave the tab, which quietly threw away the transcript — and, worse, any
/// confirmation waiting for a tap. Walking away mid-loop meant the applied tool
/// results never reached the model, so it never learned what happened. Holding
/// the state here means navigation is just navigation.
@MainActor
@Observable
final class CoachSession {

    var messages: [AIService.Message] = []
    var pendingChanges: [PendingChange] = []
    var draft: String = ""
    var isLoading: Bool = false
    var error: String?

    /// Hide the internal tool_result turns; show only user/assistant chat.
    var visibleMessages: [AIService.Message] {
        messages.filter { $0.toolResults.isEmpty }
    }

    func clear() {
        messages.removeAll()
        pendingChanges = []
        error = nil
    }

    // MARK: - Sending

    func send(_ text: String, context: ModelContext, userName: String, companyName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AIService.Message(role: .user, content: trimmed))
        draft = ""
        runLoop(context: context, userName: userName, companyName: companyName)
    }

    /// One user message can take several round trips: the model calls a tool,
    /// reads the result, then decides what to do next. The loop runs until the
    /// model stops calling tools, a batch needs approval, or it hits
    /// `AIService.maxLoopTurns`.
    ///
    /// Confirmation suspends the loop rather than ending it — `applyChanges` and
    /// `dismissChanges` feed the results back and call this again, so the model
    /// always sees how its change landed.
    private func runLoop(context: ModelContext, userName: String, companyName: String) {
        let container = context.container
        isLoading = true
        error = nil

        Task { @MainActor in
            // Built once per user message rather than per turn: it serialises
            // every entry, and the read tools cover anything that moves.
            let taskJSON = await PayloadBuilder(modelContainer: container).build()
            let service = AIService(taskJSON: taskJSON, userName: userName, companyName: companyName)

            for _ in 1...AIService.maxLoopTurns {
                do {
                    let response = try await service.send(messages: messages)

                    guard !response.toolCalls.isEmpty else {
                        #if DEBUG
                        print("[Coach] loop ended — model returned text with no tool calls")
                        #endif
                        messages.append(AIService.Message(role: .assistant, content: response.text))
                        isLoading = false
                        return
                    }

                    messages.append(AIService.Message(role: .assistant,
                                                      content: response.text,
                                                      toolCalls: response.toolCalls))

                    let resolver = EntryResolver(context)
                    let split = CoachToolPolicy.partition(response.toolCalls, resolver: resolver)

                    if !split.confirm.isEmpty {
                        pendingChanges = split.confirm.map {
                            PendingChange(summary: describe($0, resolver: resolver), toolCall: $0)
                        }
                        isLoading = false
                        return
                    }

                    messages.append(AIService.Message(role: .user,
                                                      content: "",
                                                      toolResults: runTools(split.auto, context: context)))
                } catch {
                    self.error = error.localizedDescription
                    isLoading = false
                    return
                }
            }

            messages.append(AIService.Message(
                role: .assistant,
                content: "I stopped after \(AIService.maxLoopTurns) steps so this didn't run away. Tell me to keep going if that wasn't finished."
            ))
            isLoading = false
        }
    }

    // MARK: - Applying

    /// Runs a batch and saves once. Reads never touch the store, so a read-only
    /// batch skips the save entirely.
    private func runTools(_ calls: [CoachToolCall], context: ModelContext) -> [ToolResultBlock] {
        var blocks: [ToolResultBlock] = []
        var didWrite = false

        for call in calls {
            let output: String
            if CoachToolPolicy.isRead(call) {
                output = CoachToolReader.execute(call, context: context)
            } else {
                output = CoachToolExecutor.execute(call, context: context)
                didWrite = true
            }
            #if DEBUG
            // The failure that matters here is the model *claiming* a change it
            // never made, which is invisible from the transcript alone.
            print("[Coach] tool \(call.name) input=\(call.inputJSON)")
            print("[Coach]   -> \(output)")
            #endif
            blocks.append(ToolResultBlock(toolUseID: call.id, content: output))
        }

        // One save for the whole batch — the same main-context path the task
        // editor uses for a single-field change, which merges cleanly.
        if didWrite { try? context.save() }
        return blocks
    }

    func applyChanges(context: ModelContext, userName: String, companyName: String) {
        let calls = pendingChanges.map { $0.toolCall }
        pendingChanges = []
        messages.append(AIService.Message(role: .user,
                                          content: "",
                                          toolResults: runTools(calls, context: context)))
        // Hand the results back so the model reports what actually happened
        // instead of the view inventing a summary.
        runLoop(context: context, userName: userName, companyName: companyName)
    }

    func dismissChanges(context: ModelContext, userName: String, companyName: String) {
        let results = pendingChanges.map {
            ToolResultBlock(toolUseID: $0.toolCall.id,
                            content: "The user declined this change. Do not retry it — acknowledge and move on.")
        }
        pendingChanges = []
        messages.append(AIService.Message(role: .user, content: "", toolResults: results))
        runLoop(context: context, userName: userName, companyName: companyName)
    }

    // MARK: - Change Summaries (read-only)

    func describe(_ call: CoachToolCall, resolver: EntryResolver) -> String {
        func one(_ key: String) -> String {
            guard let id = call.string(key), let e = resolver.entry(id) else { return "that task" }
            return "\"\(CoachToolFormat.name(e))\""
        }

        func names(_ key: String) -> String {
            let ids = call.stringArray(key)
            let entries = resolver.entries(ids)
            if entries.isEmpty { return "\(ids.count) task(s)" }
            let ns = entries.map { CoachToolFormat.name($0) }
            if ns.count == 1 { return "\"\(ns[0])\"" }
            if ns.count <= 3 { return ns.map { "\"\($0)\"" }.joined(separator: ", ") }
            return "\(ns.count) tasks"
        }

        switch call.name {
        case "starTasks":       return "Star \(names("taskIds"))"
        case "unstarTasks":     return "Unstar \(names("taskIds"))"
        case "updateDueDate":
            if let shift = call.string("shift") {
                return "Move due date for \(names("taskIds")) to \(CoachToolFormat.shiftLabel(shift))"
            } else if let ds = call.string("dueDate") {
                return "Set due date for \(names("taskIds")) to \(ds)"
            }
            return "Update due date for \(names("taskIds"))"
        case "updateTaskStatus":
            let raw = call.string("status") ?? ""
            return "Mark \(names("taskIds")) as \(CoachToolFormat.statusFrom(raw).map(CoachToolFormat.statusLabel) ?? raw)"
        case "bulkUpdate":
            return "Apply \(call.objectArray("updates").count) changes to tasks"
        case "addTime":
            let mins = call.double("minutes") ?? 0
            let when = call.string("date").flatMap(CoachToolFormat.parseDate) ?? Date()
            return "Log \(CoachToolFormat.duration(mins)) to \(one("taskId")) on \(CoachToolFormat.day(when))"
        case "addSubtask":
            let done = (call.bool("done") ?? false) ? " (done)" : ""
            return "Add subtask \"\(call.string("title") ?? "")\"\(done) to \(one("taskId"))"
        case "updateSubtask":
            let done = (call.bool("done") ?? true) ? "done" : "not done"
            return "Mark subtask \"\(call.string("title") ?? "")\" on \(one("taskId")) as \(done)"
        case "createTask":
            return "Create \"\(call.string("description") ?? "")\" for \(call.string("client") ?? "a client")"
        case "startTimer":      return "Start timer on \(one("taskId"))"
        case "stopTimer":       return "Stop timer on \(one("taskId"))"
        default:                return call.name
        }
    }
}
