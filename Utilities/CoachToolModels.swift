import Foundation

/// A single tool call parsed from a Claude Coach response.
///
/// The tool input is stored as a JSON **string**, not `[String: Any]`. A stored
/// `[String: Any]` puts an `Any` existential into the view layer (this struct
/// flows through `AIService.Message` into `ChatBubble`), and SwiftUI's
/// AttributeGraph structurally compares view inputs on every layout pass —
/// comparing `Any` existentials is pathologically slow and was hanging the chat
/// view on scroll. A `String` compares cheaply. Callers that need the structured
/// input read the `input` computed property, which parses on demand.
struct CoachToolCall: Identifiable, Equatable {
    let id: String          // Anthropic tool_use id — pairs with the tool_result
    let name: String
    let inputJSON: String

    init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        if let data = try? JSONSerialization.data(withJSONObject: input),
           let json = String(data: data, encoding: .utf8) {
            self.inputJSON = json
        } else {
            self.inputJSON = "{}"
        }
    }

    // tool_use ids are unique, so identity is sufficient for equality.
    static func == (lhs: CoachToolCall, rhs: CoachToolCall) -> Bool { lhs.id == rhs.id }

    /// Parsed input. Recomputed on access — never stored, so no existential
    /// reaches SwiftUI's view comparison.
    var input: [String: Any] {
        guard let data = inputJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    // MARK: Typed accessors

    func string(_ key: String) -> String? { input[key] as? String }

    func bool(_ key: String) -> Bool? { input[key] as? Bool }

    /// Numbers arrive as Int, Double or String depending on how the model
    /// serialised them — accept all three rather than silently reading nil.
    func double(_ key: String) -> Double? {
        let value = input[key]
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }

    func int(_ key: String) -> Int? { double(key).map { Int($0) } }

    func stringArray(_ key: String) -> [String] {
        let value = input[key]
        if let arr = value as? [String] { return arr }
        if let arr = value as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    func objectArray(_ key: String) -> [[String: Any]] {
        let value = input[key]
        if let arr = value as? [[String: Any]] { return arr }
        if let arr = value as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        return []
    }
}

/// A human-readable change awaiting user confirmation.
struct PendingChange: Identifiable, Equatable {
    let id = UUID()
    let summary: String
    let toolCall: CoachToolCall

    static func == (lhs: PendingChange, rhs: PendingChange) -> Bool { lhs.id == rhs.id }
}

/// One tool_result block sent back to the API after a change is applied or dismissed.
struct ToolResultBlock: Equatable {
    let toolUseID: String
    let content: String
}

/// Parsed Coach reply: conversational text plus any proposed tool calls.
struct CoachResponse {
    let text: String
    let toolCalls: [CoachToolCall]
}
