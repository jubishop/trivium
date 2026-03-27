import Foundation

final class ClaudeService: AgentService, @unchecked Sendable {
    private let executablePath: String?
    private var currentProcess: Process?
    private let lock = NSLock()
    var permissionsDir: String?

    init(executablePath: String?) {
        self.executablePath = executablePath
    }

    func respondToPermission(requestID: String, granted: Bool) {
        // Claude permissions go through file IPC, not the process stdin.
        // PermissionFileWatcher handles writing the response file.
    }

    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent> {
        cancel()

        return AsyncStream { continuation in
            guard let executablePath = self.executablePath else {
                continuation.yield(.error("Claude CLI not found. \(AgentType.claude.executableLookupHint)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)

            var env = AgentType.processEnvironment
            if let permissionsDir = self.permissionsDir {
                env["TRIVIUM_PERMISSIONS_DIR"] = permissionsDir
            }
            process.environment = env

            var args = [
                "-p",
                "--output-format", "stream-json",
                "--include-partial-messages",
            ]

            // Configure PreToolUse hook for permission handling
            let hookBinaryPath = self.hookBinaryPath
            if FileManager.default.isExecutableFile(atPath: hookBinaryPath), self.permissionsDir != nil {
                let settingsJSON = "{\"hooks\":{\"PreToolUse\":[{\"matcher\":\"\",\"hooks\":[{\"type\":\"command\",\"command\":\"\(hookBinaryPath)\"}]}]}}"
                args.append(contentsOf: ["--settings", settingsJSON])
            }

            if let sessionID {
                args.append(contentsOf: ["--resume", sessionID])
            }

            args.append(prompt)

            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            Log.info("[Claude] Launching: \(executablePath) \(args.joined(separator: " "))")
            Log.info("[Claude] cwd: \(workingDirectory)")

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            lock.lock()
            currentProcess = process
            lock.unlock()

            var capturedSessionID: String?
            var fullText = ""
            let lifecycle = ProcessStreamCoordinator(label: "Claude", continuation: continuation)

            process.terminationHandler = { [weak self] proc in
                Log.info("[Claude] Process terminated with code \(proc.terminationStatus)")
                lifecycle.markTerminated(status: proc.terminationStatus)

                self?.lock.lock()
                if self?.currentProcess === proc {
                    self?.currentProcess = nil
                }
                self?.lock.unlock()
            }

            do {
                try process.run()
                Log.info("[Claude] Process started, pid=\(process.processIdentifier)")
            } catch {
                Log.error("[Claude] Failed to launch: \(error.localizedDescription)")
                continuation.yield(.error("Failed to launch Claude CLI: \(error.localizedDescription)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            Task.detached {
                for await line in StreamParser.lines(from: stdout.fileHandleForReading) {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }

                    switch type {
                    case "system":
                        if let subtype = json["subtype"] as? String, subtype == "init",
                           let sid = json["session_id"] as? String {
                            capturedSessionID = sid
                            Log.info("[Claude] Session started: \(sid)")
                            continuation.yield(.sessionStarted(id: sid))
                        }

                    case "stream_event":
                        guard let event = json["event"] as? [String: Any],
                              let eventType = event["type"] as? String else { continue }

                        if eventType == "content_block_start" {
                            if let contentBlock = event["content_block"] as? [String: Any],
                               let blockType = contentBlock["type"] as? String,
                               blockType == "tool_use",
                               let toolID = contentBlock["id"] as? String,
                               let toolName = contentBlock["name"] as? String {
                                continuation.yield(.toolUseStarted(id: toolID, name: toolName))
                            }
                            if !fullText.isEmpty {
                                fullText += "\n\n"
                                continuation.yield(.textDelta("\n\n"))
                            }
                        } else if eventType == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String, deltaType == "text_delta",
                           let text = delta["text"] as? String {
                            fullText += text
                            continuation.yield(.textDelta(text))
                        }

                    case "result":
                        if let result = json["result"] as? String {
                            Log.info("[Claude] Result received, length=\(result.count)")
                            continuation.yield(.textComplete(result))
                        }
                        if let sid = json["session_id"] as? String, capturedSessionID == nil {
                            capturedSessionID = sid
                            continuation.yield(.sessionStarted(id: sid))
                        }
                        if let isError = json["is_error"] as? Bool, isError,
                           let errMsg = json["result"] as? String {
                            Log.error("[Claude] API error: \(errMsg)")
                            continuation.yield(.error(errMsg))
                        }

                    default:
                        break
                    }
                }
                Log.info("[Claude] stdout stream ended")
                lifecycle.markStdoutFinished()
            }

            Task.detached {
                for await line in StreamParser.lines(from: stderr.fileHandleForReading) {
                    lifecycle.appendStderrLine(line)
                }
                lifecycle.markStderrFinished()
            }
        }
    }

    func cancel() {
        lock.lock()
        let proc = currentProcess
        currentProcess = nil
        lock.unlock()

        if let proc, proc.isRunning {
            Log.info("[Claude] Cancelling process pid=\(proc.processIdentifier)")
            proc.terminate()
        }
    }

    private var hookBinaryPath: String {
        // Look next to the MCP server binary first, then fall back to repo root
        let candidates = [
            Bundle.main.bundlePath + "/../trivium-permission-hook",
            (Bundle.main.bundlePath as NSString).deletingLastPathComponent + "/trivium-permission-hook",
            NSHomeDirectory() + "/Desktop/trivium/trivium-permission-hook",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "trivium-permission-hook"
    }
}
