import Foundation

final class CodexService: AgentService, @unchecked Sendable {
    private let executablePath: String?
    private var currentProcess: Process?
    private let lock = NSLock()

    init(executablePath: String?) {
        self.executablePath = executablePath
    }

    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent> {
        cancel()

        return AsyncStream { continuation in
            guard let executablePath = self.executablePath else {
                continuation.yield(.error("Codex CLI not found. \(AgentType.codex.executableLookupHint)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.environment = AgentType.processEnvironment

            var args: [String]

            if let sessionID {
                args = [
                    "exec", "resume",
                    "--json",
                    "--full-auto",
                    sessionID,
                    prompt,
                ]
            } else {
                args = [
                    "exec",
                    "--json",
                    "--full-auto",
                    "--skip-git-repo-check",
                    "-C", workingDirectory,
                    prompt,
                ]
            }

            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            Log.info("[Codex] Launching: \(executablePath) \(args.joined(separator: " "))")
            Log.info("[Codex] cwd: \(workingDirectory)")

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = Pipe()

            lock.lock()
            currentProcess = process
            lock.unlock()

            let lifecycle = ProcessStreamCoordinator(label: "Codex", continuation: continuation)

            process.terminationHandler = { [weak self] proc in
                Log.info("[Codex] Process terminated with code \(proc.terminationStatus)")
                lifecycle.markTerminated(status: proc.terminationStatus)

                self?.lock.lock()
                if self?.currentProcess === proc {
                    self?.currentProcess = nil
                }
                self?.lock.unlock()
            }

            do {
                try process.run()
                Log.info("[Codex] Process started, pid=\(process.processIdentifier)")
            } catch {
                Log.error("[Codex] Failed to launch: \(error.localizedDescription)")
                continuation.yield(.error("Failed to launch Codex CLI: \(error.localizedDescription)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            Task.detached {
                var fullText = ""

                for await line in StreamParser.lines(from: stdout.fileHandleForReading) {
                    Log.info("[Codex] stdout: \(String(line.prefix(200)))")

                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }

                    switch type {
                    case "thread.started":
                        if let threadID = json["thread_id"] as? String {
                            Log.info("[Codex] Thread started: \(threadID)")
                            continuation.yield(.sessionStarted(id: threadID))
                        }

                    case "item.completed":
                        guard let item = json["item"] as? [String: Any],
                              let itemType = item["type"] as? String else { continue }

                        Log.info("[Codex] item.completed type=\(itemType)")
                        if itemType == "agent_message",
                           let text = item["text"] as? String {
                            // Stream each intermediate agent message as it arrives
                            if !fullText.isEmpty {
                                fullText += "\n\n"
                                continuation.yield(.textDelta("\n\n"))
                            }
                            fullText += text
                            continuation.yield(.textDelta(text))
                        }

                    case "turn.completed":
                        Log.info("[Codex] turn.completed, fullText length=\(fullText.count)")
                        if !fullText.isEmpty {
                            continuation.yield(.textComplete(fullText))
                        }

                    default:
                        break
                    }
                }
                Log.info("[Codex] stdout stream ended")
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
            Log.info("[Codex] Cancelling process pid=\(proc.processIdentifier)")
            proc.terminate()
        }
    }
}
