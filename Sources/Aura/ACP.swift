import AppKit
import Observation

/// Runs a coding agent over the Agent Client Protocol (JSON-RPC 2.0, one JSON object per line on stdio)
/// so "Get Wallpapers" can send the prompt straight to Claude Code, Codex or Gemini CLI.
/// Aura declares no fs/terminal capabilities: the agent uses its own tools and asks permission through us.
@MainActor @Observable
final class ACPSession {
    enum Phase: Equatable {
        case idle, starting, running, finished(String), failed(String)
    }

    struct ToolCall: Identifiable {
        let id: String
        var title: String
        var kind: String
        var status: String
    }

    struct PermissionRequest: Identifiable {
        struct Option: Identifiable {
            let id: String
            let name: String
            let kind: String
        }
        let id = UUID()
        let rpcID: Any
        let title: String
        let options: [Option]
    }

    private(set) var phase: Phase = .idle
    private(set) var agent: AgentTarget?
    private(set) var transcript = ""
    private(set) var tools: [ToolCall] = []
    private(set) var permissions: [PermissionRequest] = []
    /// "Allow All" for the current run: later requests are approved without asking.
    private(set) var allowAll = false

    var isActive: Bool { phase == .starting || phase == .running }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var stderrTail = ""
    @ObservationIgnored private var nextID = 1
    @ObservationIgnored private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    @ObservationIgnored private var sessionID: String?

    func run(_ agent: AgentTarget, prompt: String) async {
        guard !isActive, let (tool, args) = agent.acpCommand else { return }
        self.agent = agent
        phase = .starting
        transcript = ""
        tools = []
        permissions = []
        allowAll = false
        stderrTail = ""

        let path = await LoginShell.path()
        guard LoginShell.find(tool, in: path) != nil else {
            phase = .failed(tool == "npx"
                ? "Node.js isn't installed (needed for npx). Install it from nodejs.org, then try again."
                : "\(tool) isn't installed. Install \(agent.rawValue) first, then try again.")
            return
        }

        do {
            try launch(tool: tool, args: args, path: path)
            _ = try await request("initialize", [
                "protocolVersion": 1,
                "clientCapabilities": ["fs": ["readTextFile": false, "writeTextFile": false], "terminal": false],
                "clientInfo": ["name": "Aura", "version": Updater.shared.currentVersion],
            ])
            let session = try await request("session/new", ["cwd": LibraryStore.root.path, "mcpServers": [Any]()])
            guard let id = session["sessionId"] as? String else { throw DownloadError(message: "The agent didn't start a session") }
            sessionID = id
            phase = .running
            let result = try await request("session/prompt", ["sessionId": id, "prompt": [["type": "text", "text": prompt]]])
            let reason = result["stopReason"] as? String ?? "end_turn"
            phase = reason == "cancelled" ? .finished("Stopped") : .finished(reason == "end_turn" ? "Done" : reason.replacingOccurrences(of: "_", with: " "))
        } catch {
            if isActive { phase = .failed(Self.friendly(error.localizedDescription, stderr: stderrTail, agent: agent)) }
        }
        shutdown()
    }

    /// Answers a permission request. `nil` means cancelled.
    func respond(_ request: PermissionRequest, optionID: String?) {
        permissions.removeAll { $0.id == request.id }
        Notifier.shared.clear(request.id)
        let outcome: [String: Any] = optionID.map { ["outcome": "selected", "optionId": $0] } ?? ["outcome": "cancelled"]
        write(["jsonrpc": "2.0", "id": request.rpcID, "result": ["outcome": outcome]])
    }

    /// Approves this request and every later one in this run.
    func approveAll(_ request: PermissionRequest) {
        allowAll = true
        respond(request, optionID: Self.allowOption(request)?.id)
        permissions.forEach { respond($0, optionID: Self.allowOption($0)?.id) }
    }

    func allow(_ request: PermissionRequest) {
        respond(request, optionID: (request.options.first { $0.kind == "allow_once" } ?? Self.allowOption(request))?.id)
    }

    func deny(_ request: PermissionRequest) {
        respond(request, optionID: request.options.first { $0.kind == "reject_once" }?.id ?? request.options.first { $0.kind.hasPrefix("reject") }?.id)
    }

    /// Prefers "always" so the agent remembers too, then "once".
    private static func allowOption(_ request: PermissionRequest) -> PermissionRequest.Option? {
        request.options.first { $0.kind == "allow_always" } ?? request.options.first { $0.kind == "allow_once" }
    }

    func stop() {
        guard isActive else { return }
        permissions.forEach { respond($0, optionID: nil) }
        if let sessionID { write(["jsonrpc": "2.0", "method": "session/cancel", "params": ["sessionId": sessionID]]) }
        let proc = process
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if proc?.isRunning == true { proc?.terminate() } }
    }

    // MARK: - Transport

    private func launch(tool: String, args: [String], path: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool] + args
        p.currentDirectoryURL = LibraryStore.root
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        p.environment = env

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.stderrTail = String(((self?.stderrTail ?? "") + text).suffix(1500)) } }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.processEnded() } }
        }
        try p.run()
        process = p
        input = stdin.fileHandleForWriting
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    private func write(_ message: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(message) }
        }
    }

    private func handle(_ message: [String: Any]) {
        let method = message["method"] as? String
        let params = message["params"] as? [String: Any] ?? [:]

        switch (method, message["id"]) {
        case (nil, let id as Int):
            // Response to one of our requests.
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let error = message["error"] as? [String: Any] {
                continuation.resume(throwing: DownloadError(message: error["message"] as? String ?? "Agent error"))
            } else {
                continuation.resume(returning: message["result"] as? [String: Any] ?? [:])
            }
        case ("session/request_permission", let id?):
            let tool = params["toolCall"] as? [String: Any]
            let options = (params["options"] as? [[String: Any]] ?? []).compactMap { o -> PermissionRequest.Option? in
                guard let id = o["optionId"] as? String else { return nil }
                return .init(id: id, name: o["name"] as? String ?? id, kind: o["kind"] as? String ?? "")
            }
            let toolID = tool?["toolCallId"] as? String
            let title = tool?["title"] as? String ?? tools.first { $0.id == toolID }?.title ?? "The agent wants to run a tool"
            let request = PermissionRequest(rpcID: id, title: title, options: options)
            if allowAll, let allow = Self.allowOption(request) {
                write(["jsonrpc": "2.0", "id": id, "result": ["outcome": ["outcome": "selected", "optionId": allow.id]]])
            } else {
                permissions.append(request)
                Notifier.shared.permissionNeeded(request, agent: agent?.rawValue ?? "Your agent")
            }
        case (_?, let id?):
            // fs/terminal and anything else we didn't offer.
            write(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Not supported by Aura"]])
        case ("session/update", nil):
            if let update = params["update"] as? [String: Any] { apply(update) }
        default:
            break
        }
    }

    private func apply(_ update: [String: Any]) {
        switch update["sessionUpdate"] as? String {
        case "agent_message_chunk":
            if let content = update["content"] as? [String: Any], let text = content["text"] as? String { transcript += text }
        case "tool_call":
            guard let id = update["toolCallId"] as? String else { return }
            tools.append(ToolCall(id: id, title: update["title"] as? String ?? "Tool",
                                  kind: update["kind"] as? String ?? "other", status: update["status"] as? String ?? "pending"))
        case "tool_call_update":
            guard let id = update["toolCallId"] as? String, let i = tools.firstIndex(where: { $0.id == id }) else { return }
            if let title = update["title"] as? String { tools[i].title = title }
            if let kind = update["kind"] as? String { tools[i].kind = kind }
            if let status = update["status"] as? String { tools[i].status = status }
        default:
            break
        }
    }

    private func processEnded() {
        let error = DownloadError(message: "The agent quit unexpectedly")
        pending.values.forEach { $0.resume(throwing: error) }
        pending = [:]
        permissions = []
        if isActive { phase = .failed(Self.friendly(error.message, stderr: stderrTail, agent: agent)) }
        process = nil
        input = nil
    }

    private func shutdown() {
        try? input?.close() // agents exit when stdin closes
        let proc = process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if proc?.isRunning == true { proc?.terminate() } }
    }

    private static func friendly(_ message: String, stderr: String, agent: AgentTarget?) -> String {
        let all = (message + " " + stderr).lowercased()
        let signIn = ["not logged in", "please log in", "/login", "authentication required", "invalid api key", "unauthorized", "auth_required"]
        if signIn.contains(where: all.contains) {
            return "\(agent?.rawValue ?? "The agent") needs you to sign in. Run it once in Terminal, sign in, then try again."
        }
        let tail = stderr.split(separator: "\n").last.map(String.init) ?? ""
        return tail.isEmpty ? message : "\(message): \(tail)"
    }
}

/// GUI apps start with a bare PATH; agents live in Homebrew, ~/.local/bin and so on.
enum LoginShell {
    @MainActor private static var cached: String?

    @MainActor
    static func path() async -> String {
        if let cached { return cached }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let resolved = await Task.detached { () -> String in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = ["-lic", "printf '__AURA_PATH__%s' \"$PATH\""]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return "" }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            guard let marker = text.range(of: "__AURA_PATH__") else { return "" }
            return String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        let fallback = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        cached = resolved.isEmpty ? fallback : resolved + ":" + fallback
        return cached!
    }

    static func find(_ tool: String, in path: String) -> String? {
        path.split(separator: ":").map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
