import Foundation
import UniformTypeIdentifiers

actor ACPAgentSessionService {
    private var connections: [UUID: ACPConnection] = [:]

    func streamPrompt(
        prompt: String,
        attachments: [String],
        agent: AgentConfig,
        node: WorkflowNode,
        workspacePath: String?,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        let connection = try await connection(for: node, agent: agent, workspacePath: workspacePath)
        continuation.onTermination = { _ in
            Task {
                await connection.cancel()
            }
        }
        try await connection.prompt(prompt, attachments: attachments) { chunk in
            continuation.yield(chunk)
        }
        continuation.finish()
    }

    func cancel(nodeId: UUID) async {
        await connections[nodeId]?.cancel()
    }

    func close(nodeId: UUID) async {
        guard let connection = connections.removeValue(forKey: nodeId) else { return }
        await connection.close()
    }

    func closeAll() async {
        let activeConnections = Array(connections.values)
        connections.removeAll()
        for connection in activeConnections {
            await connection.close()
        }
    }

    func test(agent: AgentConfig, workspacePath: String?) async -> String {
        let node = WorkflowNode(
            title: "ACP Test",
            description: "Temporary ACP test node.",
            kind: .agent,
            modelId: nil,
            agentExecutable: agent.executable,
            position: CanvasPoint(x: 0, y: 0),
            inputModalities: [.text],
            outputModalities: [.text],
            chat: [],
            draftMessage: ""
        )
        let connection = ACPConnection(agent: agent, node: node, workspacePath: workspacePath)
        do {
            try await connection.start()
            await connection.close()
            return "ACP connected."
        } catch {
            await connection.close()
            let details = connection.diagnosticLog.trimmingCharacters(in: .whitespacesAndNewlines)
            return details.isEmpty ? "ACP failed: \(error.localizedDescription)" : "ACP failed: \(error.localizedDescription)\n\(details)"
        }
    }

    private func connection(for node: WorkflowNode, agent: AgentConfig, workspacePath: String?) async throws -> ACPConnection {
        if let existing = connections[node.id], existing.isRunning {
            return existing
        }
        let connection = ACPConnection(agent: agent, node: node, workspacePath: workspacePath)
        try await connection.start()
        connections[node.id] = connection
        return connection
    }
}

private final class ACPConnection: @unchecked Sendable {
    private let agent: AgentConfig
    private let node: WorkflowNode
    private let workspacePath: String?
    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var stdoutBuffer = Data()
    private var requestId = 0
    private var sessionId: String?
    private var pending: [Int: CheckedContinuation<[String: Any]?, Error>] = [:]
    private var terminals: [String: ACPTerminalSession] = [:]
    private var diagnosticText = ""
    private var chunkHandler: ((String) -> Void)?

    init(agent: AgentConfig, node: WorkflowNode, workspacePath: String?) {
        self.agent = agent
        self.node = node
        self.workspacePath = workspacePath
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let process else { return false }
        return process.isRunning
    }

    var diagnosticLog: String {
        locked { diagnosticText }
    }

    func start() async throws {
        guard agent.isAvailable || agent.path != nil || agent.acpInvocationTemplate.contains("npx ") else {
            throw ACPError.message("\(agent.name) is not available. Run Scan Agents or install \(agent.executable).")
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let command = resolvedCommand()
        let workingDirectory = workspacePath ?? FileManager.default.homeDirectoryForCurrentUser.path
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-lc", "cd \(shellQuoted(workingDirectory)); \(command)"]
        process.environment = shellEnvironment()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        error.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.emit("[ACP] \(text)")
        }

        process.terminationHandler = { [weak self] _ in
            self?.failAll(ACPError.message("\(self?.agent.name ?? "Agent") ACP process exited."))
        }

        try process.run()
        locked {
            self.process = process
            self.stdin = input.fileHandleForWriting
        }

        _ = try await request(method: "initialize", params: [
            "protocolVersion": 1,
            "clientCapabilities": [
                "promptCapabilities": [
                    "image": true,
                    "audio": true,
                    "embeddedContext": true
                ],
                "fs": [
                    "readTextFile": true,
                    "writeTextFile": true
                ],
                "terminal": true
            ],
            "clientInfo": [
                "name": "workflow-generator",
                "title": "Workflow Generator",
                "version": "0.1.0"
            ]
        ])

        let result = try await request(method: "session/new", params: [
            "cwd": workingDirectory,
            "mcpServers": []
        ])
        guard let id = result?["sessionId"] as? String, !id.isEmpty else {
            throw ACPError.message("\(agent.name) did not return an ACP session id.")
        }
        locked {
            sessionId = id
        }
    }

    func prompt(_ text: String, attachments: [String], onChunk: @escaping (String) -> Void) async throws {
        let id = currentSessionId()
        guard !id.isEmpty else { throw ACPError.message("ACP session is not ready.") }
        locked {
            chunkHandler = onChunk
        }
        defer {
            locked {
                chunkHandler = nil
            }
        }
        let beforeFiles = workspaceFileSnapshot()
        _ = try await request(method: "session/prompt", params: [
            "sessionId": id,
            "prompt": promptContent(text: text, attachments: attachments)
        ])
        emitWorkspaceFileChanges(since: beforeFiles)
    }

    func cancel() async {
        let id = currentSessionId()
        guard !id.isEmpty else { return }
        try? notify(method: "session/cancel", params: ["sessionId": id])
    }

    func close() async {
        let process = locked {
            let process = self.process
            self.process = nil
            stdin = nil
            return process
        }
        process?.terminate()
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any]? {
        let id = nextRequestId()
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending[id] = continuation
            lock.unlock()
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.timeoutNanoseconds(for: method))
                self.timeoutRequest(id: id, method: method)
            }
            do {
                try send(message)
            } catch {
                lock.lock()
                pending.removeValue(forKey: id)
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    private func timeoutRequest(id: Int, method: String) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: ACPError.message("ACP timed out while waiting for \(method). The subprocess started but did not answer JSON-RPC. Check: 1) node/npx is visible to the app, 2) the ACP bridge command is correct, 3) the bridge is not waiting for login or first-time install. Current PATH: \(shellEnvironment()["PATH"] ?? "")"))
    }

    private func timeoutNanoseconds(for method: String) -> UInt64 {
        switch method {
        case "initialize", "session/new":
            120_000_000_000
        case "session/prompt":
            1_200_000_000_000
        default:
            120_000_000_000
        }
    }

    private func notify(method: String, params: [String: Any]) throws {
        try send([
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ])
    }

    private func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else {
            throw ACPError.message("Failed to encode ACP message.")
        }
        lock.lock()
        let handle = stdin
        lock.unlock()
        guard let handle else { throw ACPError.message("ACP stdin is closed.") }
        handle.write(line)
    }

    private func consume(_ data: Data) {
        lock.lock()
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 10) {
            let lineData = stdoutBuffer.prefix(upTo: newline)
            stdoutBuffer.removeSubrange(...newline)
            lock.unlock()
            handleLine(lineData)
            lock.lock()
        }
        lock.unlock()
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emit("[ACP stdout] \(text)\n")
            }
            return
        }

        if let id = object["id"] as? Int {
            if let method = object["method"] as? String {
                handleClientRequest(id: id, method: method, params: object["params"] as? [String: Any])
            } else {
                completeRequest(id: id, object: object)
            }
            return
        }

        guard let method = object["method"] as? String else { return }
        if method == "session/update" {
            handleSessionUpdate(object["params"] as? [String: Any])
        }
    }

    private func handleClientRequest(id: Int, method: String, params: [String: Any]?) {
        do {
            switch method {
            case "session/request_permission":
                try respond(id: id, result: permissionResult(from: params))
            case "fs/read_text_file", "fs/readTextFile":
                try respond(id: id, result: try readTextFile(params))
            case "fs/write_text_file", "fs/writeTextFile":
                try writeTextFile(params)
                try respond(id: id, result: NSNull())
            case "terminal/create":
                try respond(id: id, result: try createTerminal(params))
            case "terminal/output":
                try respond(id: id, result: try terminalOutput(params))
            case "terminal/wait_for_exit":
                waitForTerminalExit(id: id, params: params)
            case "terminal/kill":
                try killTerminal(params)
                try respond(id: id, result: NSNull())
            case "terminal/release":
                try releaseTerminal(params)
                try respond(id: id, result: NSNull())
            default:
                try respondError(id: id, code: -32601, message: "Workflow Generator has not implemented ACP client method \(method).")
            }
        } catch {
            try? respondError(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func completeRequest(id: Int, object: [String: Any]) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        guard let continuation else { return }
        if let error = object["error"] as? [String: Any] {
            continuation.resume(throwing: ACPError.message(error["message"] as? String ?? "\(error)"))
        } else {
            continuation.resume(returning: object["result"] as? [String: Any])
        }
    }

    private func handleSessionUpdate(_ params: [String: Any]?) {
        guard let update = params?["update"] as? [String: Any],
              let type = update["sessionUpdate"] as? String else { return }

        switch type {
        case "agent_message_chunk":
            if let content = update["content"] as? [String: Any],
               let text = content["text"] as? String {
                emit(text)
            }
        case "agent_thought_chunk", "thought_chunk":
            if let content = update["content"] as? [String: Any],
               let text = content["text"] as? String {
                appendDiagnostic("[thought] \(text)")
            }
        case "tool_call":
            let title = update["title"] as? String ?? "Tool call"
            let status = update["status"] as? String ?? "pending"
            emit("\n[\(title): \(status)]\n")
        case "tool_call_update":
            let status = update["status"] as? String ?? "updated"
            emit("\n[tool \(status)]\n")
        case "plan":
            emit(planSummary(from: update))
        default:
            break
        }
    }

    private func respond(id: Int, result: Any) throws {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        try send(response)
    }

    private func respondError(id: Int, code: Int, message: String) throws {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        try send(response)
    }

    private func emit(_ text: String) {
        lock.lock()
        let handler = chunkHandler
        if handler == nil {
            diagnosticText += text
            if diagnosticText.count > 12_000 {
                diagnosticText = String(diagnosticText.suffix(12_000))
            }
        }
        lock.unlock()
        handler?(text)
    }

    private func appendDiagnostic(_ text: String) {
        lock.lock()
        diagnosticText += text
        if diagnosticText.count > 12_000 {
            diagnosticText = String(diagnosticText.suffix(12_000))
        }
        lock.unlock()
    }

    private func failAll(_ error: Error) {
        lock.lock()
        let continuations = pending
        pending.removeAll()
        lock.unlock()
        continuations.values.forEach { $0.resume(throwing: error) }
    }

    private func nextRequestId() -> Int {
        lock.lock()
        defer { lock.unlock() }
        requestId += 1
        return requestId
    }

    private func currentSessionId() -> String {
        lock.lock()
        defer { lock.unlock() }
        return sessionId ?? ""
    }

    private func resolvedCommand() -> String {
        let executable = agent.path ?? agent.executable
        return agent.acpInvocationTemplate.replacingOccurrences(of: "{executable}", with: executable)
    }

    private func shellEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        let commonPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"
        ]
        environment["PATH"] = (commonPaths + existingPath.split(separator: ":").map(String.init))
            .uniqued()
            .joined(separator: ":")
        return environment
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func planSummary(from update: [String: Any]) -> String {
        guard let entries = update["entries"] as? [[String: Any]], !entries.isEmpty else { return "" }
        let lines = entries.compactMap { entry -> String? in
            guard let content = entry["content"] as? String else { return nil }
            let status = entry["status"] as? String ?? "pending"
            return "- [\(status)] \(content)"
        }
        return lines.isEmpty ? "" : "\n[plan]\n\(lines.joined(separator: "\n"))\n"
    }

    private func permissionResult(from params: [String: Any]?) -> [String: Any] {
        let options = params?["options"] as? [[String: Any]] ?? []
        let allowed = options.first { option in
            let kind = (option["kind"] as? String ?? "").lowercased()
            let name = (option["name"] as? String ?? "").lowercased()
            return kind.contains("allow") || name.contains("allow") || name.contains("允许")
        } ?? options.first
        let optionId = allowed?["optionId"] as? String ?? allowed?["id"] as? String ?? "allow-once"
        let tool = (params?["toolCall"] as? [String: Any])?["title"] as? String ?? "tool call"
        emit("\n[permission: allowed \(tool)]\n")
        return ["outcome": ["outcome": "selected", "optionId": optionId]]
    }

    private func readTextFile(_ params: [String: Any]?) throws -> [String: Any] {
        guard let path = params?["path"] as? String else {
            throw ACPError.message("Missing path.")
        }
        let resolved = try allowedWorkspacePath(path)
        let content = try String(contentsOfFile: resolved, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        let start = max(0, ((params?["line"] as? Int) ?? 1) - 1)
        let limit = params?["limit"] as? Int
        let selectedLines: ArraySlice<String>
        if let limit {
            selectedLines = lines.dropFirst(start).prefix(max(0, limit))
        } else {
            selectedLines = lines.dropFirst(start)[...]
        }
        return ["content": selectedLines.joined(separator: "\n")]
    }

    private func writeTextFile(_ params: [String: Any]?) throws {
        guard let path = params?["path"] as? String,
              let content = params?["content"] as? String else {
            throw ACPError.message("Missing path or content.")
        }
        let resolved = try allowedWorkspacePath(path)
        let directory = URL(filePath: resolved).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(toFile: resolved, atomically: true, encoding: .utf8)
        emit("\n[file written: \(resolved)]\n[asset] \(resolved)\n")
    }

    private func workspaceFileSnapshot() -> [String: Date] {
        guard let workspacePath else { return [:] }
        let root = URL(filePath: workspacePath, directoryHint: .isDirectory)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return [:]
        }

        var snapshot: [String: Date] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                if shouldSkipWorkspaceDirectory(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            snapshot[url.standardizedFileURL.path] = values?.contentModificationDate ?? .distantPast
            if snapshot.count > 20_000 { break }
        }
        return snapshot
    }

    private func emitWorkspaceFileChanges(since before: [String: Date]) {
        let after = workspaceFileSnapshot()
        let changed = after
            .filter { path, modifiedAt in
                guard isUserFacingAssetPath(path) else { return false }
                guard let previous = before[path] else { return true }
                return modifiedAt.timeIntervalSince(previous) > 0.25
            }
            .sorted { first, second in
                if first.value == second.value { return first.key < second.key }
                return first.value > second.value
            }
            .map(\.key)
        guard !changed.isEmpty else { return }
        for path in changed.prefix(24) {
            emit("[asset] \(path)\n")
        }
        if changed.count > 24 {
            emit("[ACP] \(changed.count - 24) more changed files were left in the workspace.\n")
        }
    }

    private func shouldSkipWorkspaceDirectory(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased == ".git" ||
            lowercased == ".build" ||
            lowercased == "build" ||
            lowercased == "node_modules" ||
            lowercased == "deriveddata" ||
            lowercased.hasPrefix(".workflow-")
    }

    private func isUserFacingAssetPath(_ path: String) -> Bool {
        let url = URL(filePath: path)
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        let blockedExtensions = ["tmp", "lock", "log", "xcuserstate"]
        return !blockedExtensions.contains(url.pathExtension.lowercased())
    }

    private func allowedWorkspacePath(_ path: String) throws -> String {
        guard let workspacePath else {
            throw ACPError.message("No workspace is selected.")
        }
        let workspace = URL(filePath: workspacePath, directoryHint: .isDirectory).standardizedFileURL.path
        let url = URL(filePath: path).standardizedFileURL.path
        guard url == workspace || url.hasPrefix(workspace + "/") else {
            throw ACPError.message("ACP file access is limited to the selected workspace.")
        }
        return url
    }

    private func promptContent(text: String, attachments: [String]) -> [[String: Any]] {
        var blocks: [[String: Any]] = [[
            "type": "text",
            "text": text
        ]]
        for path in attachments {
            if let block = contentBlock(for: path) {
                blocks.append(block)
            }
        }
        return blocks
    }

    private func contentBlock(for path: String) -> [String: Any]? {
        let url = URL(filePath: path)
        let mimeType = mimeType(for: url)
        let modality = MediaAsset.inferModality(path: path)
        let uri = url.absoluteString
        switch modality {
        case .image:
            guard let data = try? Data(contentsOf: url) else { return resourceLink(url: url, mimeType: mimeType) }
            return [
                "type": "image",
                "mimeType": mimeType,
                "data": data.base64EncodedString(),
                "uri": uri
            ]
        case .audio:
            guard let data = try? Data(contentsOf: url) else { return resourceLink(url: url, mimeType: mimeType) }
            return [
                "type": "audio",
                "mimeType": mimeType,
                "data": data.base64EncodedString(),
                "uri": uri
            ]
        case .text:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return resourceLink(url: url, mimeType: mimeType) }
            return [
                "type": "resource",
                "resource": [
                    "uri": uri,
                    "mimeType": mimeType,
                    "text": text
                ]
            ]
        case .video, .audioVideo, .file, .json, .embedding, .scores, .music, .threeD, .mask, .bbox, .reference, .unknown:
            return resourceLink(url: url, mimeType: mimeType)
        }
    }

    private func resourceLink(url: URL, mimeType: String) -> [String: Any] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return [
            "type": "resource_link",
            "uri": url.absoluteString,
            "name": url.lastPathComponent,
            "mimeType": mimeType,
            "size": size
        ]
    }

    private func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    private func createTerminal(_ params: [String: Any]?) throws -> [String: Any] {
        guard let command = params?["command"] as? String, !command.isEmpty else {
            throw ACPError.message("Missing terminal command.")
        }
        let args = params?["args"] as? [String] ?? []
        let cwd = try allowedWorkspacePath((params?["cwd"] as? String) ?? workspacePath ?? FileManager.default.homeDirectoryForCurrentUser.path)
        let env = params?["env"] as? [[String: String]] ?? []
        let outputLimit = params?["outputByteLimit"] as? Int ?? 1_048_576
        let terminal = try ACPTerminalSession(command: command, args: args, cwd: cwd, env: env, outputByteLimit: outputLimit) { [weak self] chunk in
            self?.emit(chunk)
        }
        let terminalId = "term-\(UUID().uuidString.lowercased())"
        locked {
            terminals[terminalId] = terminal
        }
        emit("\n[terminal: \(command) \(args.joined(separator: " "))]\n")
        return ["terminalId": terminalId]
    }

    private func terminalOutput(_ params: [String: Any]?) throws -> [String: Any] {
        let terminal = try terminal(for: params)
        return terminal.outputSnapshot()
    }

    private func waitForTerminalExit(id: Int, params: [String: Any]?) {
        do {
            let terminal = try terminal(for: params)
            Task.detached { [weak self] in
                let status = terminal.waitForExit()
                try? self?.respond(id: id, result: status)
            }
        } catch {
            try? respondError(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func killTerminal(_ params: [String: Any]?) throws {
        try terminal(for: params).kill()
    }

    private func releaseTerminal(_ params: [String: Any]?) throws {
        let id = try terminalId(from: params)
        let terminal = locked {
            terminals.removeValue(forKey: id)
        }
        terminal?.kill()
    }

    private func terminal(for params: [String: Any]?) throws -> ACPTerminalSession {
        let id = try terminalId(from: params)
        guard let terminal = locked({ terminals[id] }) else {
            throw ACPError.message("Unknown terminal id: \(id)")
        }
        return terminal
    }

    private func terminalId(from params: [String: Any]?) throws -> String {
        guard let id = params?["terminalId"] as? String, !id.isEmpty else {
            throw ACPError.message("Missing terminal id.")
        }
        return id
    }
}

private final class ACPTerminalSession: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var output = ""
    private var truncated = false
    private let outputByteLimit: Int

    init(command: String, args: [String], cwd: String, env: [[String: String]], outputByteLimit: Int, onOutput: @escaping @Sendable (String) -> Void) throws {
        self.outputByteLimit = max(4096, outputByteLimit)
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [command] + args
        process.currentDirectoryURL = URL(filePath: cwd, directoryHint: .isDirectory)
        var environment = ProcessInfo.processInfo.environment
        for item in env {
            guard let name = item["name"], let value = item["value"] else { continue }
            environment[name] = value
        }
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process

        let handler: (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.append(text)
            onOutput(text)
        }
        outputPipe.fileHandleForReading.readabilityHandler = handler
        errorPipe.fileHandleForReading.readabilityHandler = handler
        try process.run()
    }

    func outputSnapshot() -> [String: Any] {
        locked {
            var result: [String: Any] = [
                "output": output,
                "truncated": truncated
            ]
            if !process.isRunning {
                result["exitStatus"] = exitStatus()
            }
            return result
        }
    }

    func waitForExit() -> [String: Any] {
        process.waitUntilExit()
        return exitStatus()
    }

    func kill() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func append(_ text: String) {
        locked {
            output += text
            if let data = output.data(using: .utf8), data.count > outputByteLimit {
                let suffix = data.suffix(outputByteLimit)
                output = String(data: suffix, encoding: .utf8) ?? String(output.suffix(outputByteLimit))
                truncated = true
            }
        }
    }

    private func exitStatus() -> [String: Any] {
        [
            "exitCode": Int(process.terminationStatus),
            "signal": NSNull()
        ]
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private enum ACPError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { item in
            guard !item.isEmpty, !seen.contains(item) else { return false }
            seen.insert(item)
            return true
        }
    }
}
