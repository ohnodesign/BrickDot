import Foundation
import Network
import SwiftData

/// Loopback bridge that lets a Claude conversation on this Mac drive BrickDot.
///
/// Why a socket rather than a file drop or a `brickdot://` URL: a tool call needs
/// an *answer* — "which task did you match, and what is the total now" — and it
/// needs it in one hop. A file bridge means polling, stale snapshots and two
/// copies of the truth; a URL scheme can carry a command but nothing back. A
/// listener on 127.0.0.1 gives request/response, is debuggable with curl, and
/// keeps every write on the same main-context path the UI already uses, so
/// CloudKit syncs it to the phone like any other edit.
///
/// Mac only, off by default, bound to loopback, and every request must carry the
/// bearer token shown in Settings — a local socket is reachable by anything else
/// running as this user, so an unauthenticated one would be an open door to the
/// billing data.
enum CoachBridge {

    static let defaultPort: UInt16 = 8787

    private static let enabledKey    = "bridge.enabled"
    private static let readOnlyKey   = "bridge.readOnly"
    private static let portKey       = "bridge.port"
    private static let tokenKey      = "bridge.token"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Lets the bridge answer questions while refusing every mutation — worth
    /// leaving on until you trust what the conversation is doing.
    static var isReadOnly: Bool {
        get { UserDefaults.standard.bool(forKey: readOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: readOnlyKey) }
    }

    static var port: UInt16 {
        get {
            let stored = UserDefaults.standard.integer(forKey: portKey)
            return stored > 0 ? UInt16(stored) : defaultPort
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: portKey) }
    }

    /// Generated once and kept — regenerating it silently breaks the MCP config.
    static var token: String {
        if let existing = UserDefaults.standard.string(forKey: tokenKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: tokenKey)
        return fresh
    }

    static func regenerateToken() {
        UserDefaults.standard.set(UUID().uuidString, forKey: tokenKey)
    }
}

// MARK: - Server

@MainActor
final class CoachBridgeServer: ObservableObject {

    static let shared = CoachBridgeServer()

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastRequest: String?

    private var listener: NWListener?
    private var container: ModelContainer?
    private nonisolated let queue = DispatchQueue(label: "com.ohnodesign.brickdot.bridge")

    private init() {}

    // MARK: Lifecycle

    func start(container: ModelContainer) {
        self.container = container
        guard CoachBridge.isEnabled, listener == nil else { return }

        do {
            let params = NWParameters.tcp
            // Deliberately NOT allowing reuse: a second BrickDot binding this
            // port would answer from its own (likely empty) store, and be
            // indistinguishable from the real one.
            params.allowLocalEndpointReuse = false
            // Loopback only. Never bind the LAN interface — this speaks for the
            // whole database and has no business being reachable off the machine.
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: .init(rawValue: CoachBridge.port)!)

            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .global())
                self?.receive(on: connection, buffer: Data())
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastError = error.localizedDescription
                        self?.stop()
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    func restart(container: ModelContainer) {
        stop()
        start(container: container)
    }

    // MARK: Connection handling

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }

            if error != nil {
                connection.cancel()
                return
            }

            // Keep reading until the headers land and the declared body is whole.
            guard let request = HTTPRequest(buffer) else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
                return
            }

            Task { @MainActor in
                let response = await CoachBridgeServer.shared.route(request)
                Self.send(response, on: connection)
            }
        }
    }

    private nonisolated static func send(_ response: (status: Int, body: String), on connection: NWConnection) {
        let body = Data(response.body.utf8)
        let head = """
        HTTP/1.1 \(response.status) \(statusText(response.status))\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        default:  return "Error"
        }
    }

    // MARK: Routing

    private func route(_ request: HTTPRequest) async -> (status: Int, body: String) {
        lastRequest = "\(request.method) \(request.path)"

        guard request.bearerToken == CoachBridge.token else {
            return (401, Self.json(["error": "Bad or missing bearer token."]))
        }
        guard let container else {
            return (503, Self.json(["error": "The app has no data container yet."]))
        }
        let ctx = container.mainContext

        switch (request.method, request.path) {

        case ("GET", "/health"):
            // Reports what the store actually is, not just that the socket
            // answered. An empty snapshot is ambiguous — no work, or a container
            // that fell through to the in-memory fallback and came up blank —
            // and guessing between those cost an evening.
            var health: [String: Any] = [
                "ok": true,
                "app": "BrickDot",
                "readOnly": CoachBridge.isReadOnly,
                "fallbackToLocal": UserDefaults.standard.bool(forKey: "cloudkit.fallbackToLocal")
            ]
            if let config = container.configurations.first {
                health["storeInMemoryOnly"] = config.isStoredInMemoryOnly
                health["storePath"] = config.url.path
            }
            do {
                health["entryCount"] = try ctx.fetchCount(FetchDescriptor<Entry>())
                health["clientCount"] = try ctx.fetchCount(FetchDescriptor<Client>())
            } catch {
                // buildPayload swallows this with `try?` and returns an empty
                // snapshot, which reads as "no work" instead of "broken".
                health["ok"] = false
                health["fetchError"] = error.localizedDescription
            }
            return (200, Self.json(health))

        case ("GET", "/snapshot"):
            return (200, TaskDataSerializer.buildPayload(context: ctx))

        case ("GET", "/tools"):
            // The full schema, so the MCP server can mirror whatever this build
            // supports instead of keeping its own copy that quietly rots.
            let payload: [String: Any] = [
                "tools": CoachToolSchema.all,
                "readOnly": CoachBridge.isReadOnly
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let body = String(data: data, encoding: .utf8) else {
                return (500, Self.json(["error": "Could not encode the tool schema."]))
            }
            return (200, body)

        case ("POST", "/tool"):
            guard let payload = request.jsonBody,
                  let name = payload["name"] as? String else {
                return (400, Self.json(["error": "Expected {\"name\": ..., \"input\": {...}}."]))
            }
            let input = payload["input"] as? [String: Any] ?? [:]
            let call = CoachToolCall(id: "bridge-\(UUID().uuidString)", name: name, input: input)

            if CoachToolPolicy.isRead(call) {
                return (200, Self.json(["ok": true, "result": CoachToolReader.execute(call, context: ctx)]))
            }
            guard CoachToolPolicy.isBridgeSafe(call) else {
                return (403, Self.json([
                    "error": "\(name) can only be run inside BrickDot, where it stops for confirmation. Ask the user to do it on the Export screen."
                ]))
            }
            guard !CoachBridge.isReadOnly else {
                return (403, Self.json(["error": "The bridge is in read-only mode. Turn it off in BrickDot Settings."]))
            }

            let result = CoachToolExecutor.execute(call, context: ctx)
            // Same save path as the task editor, so CloudKit picks the change up
            // and it reaches the phone.
            try? ctx.save()
            return (200, Self.json(["ok": true, "result": result]))

        default:
            return (404, Self.json(["error": "No route for \(request.method) \(request.path)."]))
        }
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - Minimal HTTP request

/// Just enough HTTP for one local client. Returns nil while the request is still
/// arriving, which is the signal to keep reading.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }

        guard let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        method = String(requestLine[0]).uppercased()
        path = String(requestLine[1]).components(separatedBy: "?").first ?? String(requestLine[1])

        var parsed: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            parsed[key] = value
        }
        headers = parsed

        let expected = Int(parsed["content-length"] ?? "0") ?? 0
        let bodyBytes = data[headerEnd.upperBound...]
        guard bodyBytes.count >= expected else { return nil }   // still arriving
        body = Data(bodyBytes.prefix(expected))
    }

    var bearerToken: String? {
        guard let value = headers["authorization"], value.lowercased().hasPrefix("bearer ") else { return nil }
        return String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }

    var jsonBody: [String: Any]? {
        try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
