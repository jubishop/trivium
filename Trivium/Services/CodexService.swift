import Foundation

final class CodexService: AgentService, @unchecked Sendable {
    private static let binaryPath = "/opt/homebrew/bin/codex"

    private var currentProcess: Process?
    private let lock = NSLock()

    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent> {
        cancel()

        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.binaryPath)
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

            Log.info("[Codex] Launching: \(Self.binaryPath) \(args.joined(separator: " "))")
            Log.info("[Codex] cwd: \(workingDirectory)")

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = Pipe()

            lock.lock()
            currentProcess = process
            lock.unlock()

            process.terminationHandler = { [weak self] proc in
                Log.info("[Codex] Process terminated with code \(proc.terminationStatus)")
                if proc.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "exit code \(proc.terminationStatus)"
                    let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Log.error("[Codex] stderr: \(trimmed)")
                        continuation.yield(.error(trimmed))
                    }
                }
                continuation.yield(.done)
                continuation.finish()

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
                            fullText = text
                        }

                    case "turn.completed":
                        Log.info("[Codex] turn.completed, fullText length=\(fullText.count)")
                        if !fullText.isEmpty {
                            continuation.yield(.textDelta(fullText))
                            continuation.yield(.textComplete(fullText))
                        }

                    default:
                        break
                    }
                }
                Log.info("[Codex] stdout stream ended")
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
