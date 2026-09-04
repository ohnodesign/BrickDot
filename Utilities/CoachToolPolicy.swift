import Foundation

/// Decides which Coach tool calls apply straight away and which stop for a tap.
///
/// The Coach runs an agentic loop: it can call a tool, read the result, and
/// decide what to do next. Stopping for confirmation at every step would make
/// "add two hours and tick off the editing subtask" a three-tap chore, so
/// low-risk single-task edits apply automatically. Anything that is wide
/// (several tasks at once) or touches money already sent to a client still
/// waits for Michael.
enum CoachToolPolicy {

    /// Task ids a call targets, whether the tool takes one id or many.
    static func targetIDs(_ call: CoachToolCall) -> [String] {
        if let single = call.string("taskId") { return [single] }
        let many = call.stringArray("taskIds")
        if !many.isEmpty { return many }
        return call.objectArray("updates").compactMap { $0["taskId"] as? String }
    }

    static func isRead(_ call: CoachToolCall) -> Bool {
        CoachToolSchema.readToolNames.contains(call.name)
    }

    /// True when the call must be shown to the user before it is applied.
    static func requiresConfirmation(_ call: CoachToolCall, resolver: EntryResolver) -> Bool {
        if isRead(call) { return false }

        // Mixed-intent batches are hard to summarise in one line — always ask.
        if call.name == "bulkUpdate" { return true }

        let ids = targetIDs(call)

        // A wide edit from one fuzzy match is the expensive mistake. Ask.
        if ids.count > 1 { return true }

        // Never silently rewrite work that has already gone out on an invoice.
        if resolver.entries(ids).contains(where: { $0.invoice != nil }) { return true }

        return false
    }

    /// Splits a batch into (autoApply, needsConfirmation).
    ///
    /// The API requires every `tool_use` block in an assistant turn to come back
    /// with a matching `tool_result`, so a batch cannot be answered piecemeal:
    /// if any call in it needs a tap, the whole batch waits.
    static func partition(_ calls: [CoachToolCall],
                          resolver: EntryResolver) -> (auto: [CoachToolCall], confirm: [CoachToolCall]) {
        let needsTap = calls.contains { requiresConfirmation($0, resolver: resolver) }
        return needsTap ? ([], calls) : (calls, [])
    }
}
