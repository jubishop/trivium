import Foundation

final class CodexService: AgentService, @unchecked Sendable {
    private let executablePath: String?
    private let lock = NSLock()

    // Persistent app-server process
    private var serverProcess: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var threadID: String?
    private var nextRequestID = 1
    private var isInitialized = false
    private var activeContinuation: AsyncStream<StreamEvent>.Continuation?

    // Pending JSON-RPC response IDs that the server is blocking on
    private var pendingApprovalIDs: [String: Bool] = [:]

    init(executablePath: String?) {
        self.executablePath = executablePath
    }

    func respondToPermission(requestID: String, granted: Bool) {
        lock.lock()
        let pipe = stdinPipe
        lock.unlock()

        let decision = granted ? "accept" : "decline"

        // The request ID may have been an integer from the server
        let idValue: Any = Int(requestID).map { $0 as Any } ?? requestID as Any
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": idValue,
            "result": ["decision": decision],
        ]

        guard let pipe,
              let data = try? JSONSerialization.data(withJSONObject: response),
              let line = String(data: data, encoding: .utf8) else { return }

        Log.info("[Codex] Sending approval response: \(line)")
        let lineData = Data((line + "\n").utf8)
        pipe.fileHandleForWriting.write(lineData)
    }

    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent> {
        return AsyncStream { continuation in
            self.lock.lock()
            self.activeContinuation = continuation
            self.lock.unlock()

            guard let executablePath = self.executablePath else {
                continuation.yield(.error("Codex CLI not found. \(AgentType.codex.executableLookupHint)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            // Do blocking server setup on a background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                if !self.ensureServerRunning(executablePath: executablePath, workingDirectory: workingDirectory) {
                    continuation.yield(.error("Failed to start Codex app-server"))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }

                if self.threadID == nil {
                    self.startThread(workingDirectory: workingDirectory)
                }

                let deadline = Date().addingTimeInterval(10)
                while self.threadID == nil && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }

                self.lock.lock()
                let threadID = self.threadID
                self.lock.unlock()

                guard let threadID else {
                    continuation.yield(.error("Failed to create Codex thread"))
                    continuation.yield(.done)
                    continuation.finish()
                    return
                }

                self.startTurn(threadID: threadID, prompt: prompt)
            }
        }
    }

    func cancel() {
        lock.lock()
        let cont = activeContinuation
        activeContinuation = nil
        lock.unlock()

        cont?.yield(.done)
        cont?.finish()
    }

    // MARK: - Server lifecycle

    private func ensureServerRunning(executablePath: String, workingDirectory: String) -> Bool {
        lock.lock()
        if let proc = serverProcess, proc.isRunning {
            lock.unlock()
            return true
        }
        lock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "app-server",
            "--session-source", "cli",
        ]
        process.environment = AgentType.processEnvironment
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        Log.info("[Codex] Launching app-server: \(executablePath) app-server")

        do {
            try process.run()
            Log.info("[Codex] app-server started, pid=\(process.processIdentifier)")
        } catch {
            Log.error("[Codex] Failed to launch app-server: \(error.localizedDescription)")
            return false
        }

        lock.lock()
        serverProcess = process
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        isInitialized = false
        lock.unlock()

        process.terminationHandler = { [weak self] proc in
            Log.info("[Codex] app-server terminated with code \(proc.terminationStatus)")
            self?.lock.lock()
            if self?.serverProcess === proc {
                self?.serverProcess = nil
                self?.threadID = nil
                self?.isInitialized = false
            }
            self?.lock.unlock()

            self?.lock.lock()
            let cont = self?.activeContinuation
            self?.activeContinuation = nil
            self?.lock.unlock()

            cont?.yield(.done)
            cont?.finish()
        }

        // Start reading stdout in background
        startReadingStdout(from: stdout)
        startReadingStderr(from: stderr)

        // Send initialize request
        sendInitialize()

        // Wait for initialization
        let deadline = Date().addingTimeInterval(10)
        while !isInitialized && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        return isInitialized
    }

    private func sendInitialize() {
        let params: [String: Any] = [
            "clientInfo": ["name": "Trivium", "version": "1.0"],
        ]
        sendRequest(method: "initialize", params: params)
    }

    private func startThread(workingDirectory: String) {
        let params: [String: Any] = [
            "cwd": workingDirectory,
            "approvalPolicy": "untrusted",
        ]
        sendRequest(method: "thread/start", params: params)
    }

    private func startTurn(threadID: String, prompt: String) {
        let params: [String: Any] = [
            "threadId": threadID,
            "input": [["type": "text", "text": prompt]],
        ]
        sendRequest(method: "turn/start", params: params)
    }

    private func sendRequest(method: String, params: [String: Any]) {
        lock.lock()
        let id = nextRequestID
        nextRequestID += 1
        let pipe = stdinPipe
        lock.unlock()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        guard let pipe,
              let data = try? JSONSerialization.data(withJSONObject: request),
              let line = String(data: data, encoding: .utf8) else { return }

        Log.info("[Codex] Sending: \(method) id=\(id)")
        let lineData = Data((line + "\n").utf8)
        pipe.fileHandleForWriting.write(lineData)
    }

    // MARK: - Reading

    private func startReadingStdout(from pipe: Pipe) {
        Task.detached { [weak self] in
            for await line in StreamParser.lines(from: pipe.fileHandleForReading) {
                Log.info("[Codex] stdout: \(String(line.prefix(300)))")
                self?.handleServerMessage(line)
            }
            Log.info("[Codex] stdout stream ended")
        }
    }

    private func startReadingStderr(from pipe: Pipe) {
        Task.detached {
            for await line in StreamParser.lines(from: pipe.fileHandleForReading) {
                Log.info("[Codex] stderr: \(line)")
            }
        }
    }

    private func handleServerMessage(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Distinguish requests (have "id" + "method") from notifications (have "method" only)
        // and responses (have "id" + "result"/"error")
        let hasID = json["id"] != nil
        let hasMethod = json["method"] as? String != nil
        let hasResult = json["result"] != nil || json["error"] != nil

        if hasID && hasMethod {
            handleServerRequest(json)
        } else if hasID && hasResult {
            handleServerResponse(json)
        } else if hasMethod {
            handleServerNotification(json)
        }
    }

    private func handleServerResponse(_ json: [String: Any]) {
        // Responses to our client requests (initialize, thread/start, turn/start)
        if let result = json["result"] as? [String: Any] {
            if let threadId = result["threadId"] as? String {
                lock.lock()
                threadID = threadId
                lock.unlock()
                Log.info("[Codex] Thread created: \(threadId)")

                lock.lock()
                let cont = activeContinuation
                lock.unlock()
                cont?.yield(.sessionStarted(id: threadId))
            }
            // initialize response
            if result["serverInfo"] != nil || result["capabilities"] != nil {
                lock.lock()
                isInitialized = true
                lock.unlock()
                Log.info("[Codex] Initialized")
            }
        }
    }

    private func handleServerRequest(_ json: [String: Any]) {
        guard let method = json["method"] as? String,
              let params = json["params"] as? [String: Any] else { return }

        // The id can be a string or number
        let requestID: String
        if let intID = json["id"] as? Int {
            requestID = String(intID)
        } else if let strID = json["id"] as? String {
            requestID = strID
        } else {
            return
        }

        lock.lock()
        let cont = activeContinuation
        lock.unlock()

        switch method {
        case "item/commandExecution/requestApproval":
            let command = params["command"] as? String ?? "unknown command"
            let cwd = params["cwd"] as? String
            let toolInput = cwd != nil ? "\(command)\ncwd: \(cwd!)" : command
            Log.info("[Codex] Permission requested: \(command)")
            cont?.yield(.permissionRequested(id: requestID, toolName: "Shell", toolInput: toolInput))

        case "item/fileChange/requestApproval":
            let reason = params["reason"] as? String ?? "file changes"
            Log.info("[Codex] File change approval requested: \(reason)")
            cont?.yield(.permissionRequested(id: requestID, toolName: "File Edit", toolInput: reason))

        case "item/permissions/requestApproval":
            let reason = params["reason"] as? String ?? "additional permissions"
            Log.info("[Codex] Permissions approval requested: \(reason)")
            cont?.yield(.permissionRequested(id: requestID, toolName: "Permissions", toolInput: reason))

        default:
            // Unknown request — decline it so the server doesn't hang
            Log.info("[Codex] Unknown server request: \(method), declining")
            respondToPermission(requestID: requestID, granted: false)
        }
    }

    private func handleServerNotification(_ json: [String: Any]) {
        guard let method = json["method"] as? String else { return }
        let params = json["params"] as? [String: Any] ?? [:]

        lock.lock()
        let cont = activeContinuation
        lock.unlock()

        switch method {
        case "thread/started":
            if let threadId = params["threadId"] as? String {
                lock.lock()
                threadID = threadId
                lock.unlock()
                Log.info("[Codex] Thread started: \(threadId)")
                cont?.yield(.sessionStarted(id: threadId))
            }

        case "item/completed":
            if let item = params["item"] as? [String: Any],
               let itemType = item["type"] as? String,
               itemType == "agent_message",
               let text = item["text"] as? String {
                cont?.yield(.textDelta(text + "\n\n"))
            }

        case "item/started":
            if let item = params["item"] as? [String: Any],
               let itemType = item["type"] as? String {
                if itemType == "tool_call",
                   let toolName = item["name"] as? String,
                   let toolID = item["id"] as? String {
                    cont?.yield(.toolUseStarted(id: toolID, name: toolName))
                }
            }

        case "turn/completed":
            Log.info("[Codex] Turn completed")
            cont?.yield(.done)
            cont?.finish()
            lock.lock()
            activeContinuation = nil
            lock.unlock()

        case "turn/failed":
            let error = params["error"] as? String ?? "Turn failed"
            Log.error("[Codex] Turn failed: \(error)")
            cont?.yield(.error(error))
            cont?.yield(.done)
            cont?.finish()
            lock.lock()
            activeContinuation = nil
            lock.unlock()

        case "error":
            let message = params["message"] as? String ?? "Unknown error"
            Log.error("[Codex] Error notification: \(message)")
            cont?.yield(.error(message))

        default:
            break
        }
    }

    deinit {
        serverProcess?.terminate()
    }
}
