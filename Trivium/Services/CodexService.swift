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

            var args: [String]

            if let sessionID {
                // Resume a previous session
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

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            // Provide empty stdin so codex doesn't wait for input
            process.standardInput = Pipe()

            lock.lock()
            currentProcess = process
            lock.unlock()

            process.terminationHandler = { [weak self] proc in
                if proc.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Process exited with code \(proc.terminationStatus)"
                    let trimmed = errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
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
            } catch {
                continuation.yield(.error("Failed to launch Codex CLI: \(error.localizedDescription)"))
                continuation.yield(.done)
                continuation.finish()
                return
            }

            Task.detached {
                var fullText = ""

                for await line in StreamParser.lines(from: stdout.fileHandleForReading) {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }

                    switch type {
                    case "thread.started":
                        if let threadID = json["thread_id"] as? String {
                            continuation.yield(.sessionStarted(id: threadID))
                        }

                    case "item.completed":
                        guard let item = json["item"] as? [String: Any],
                              let itemType = item["type"] as? String else { continue }

                        switch itemType {
                        case "agent_message":
                            if let text = item["text"] as? String {
                                fullText += (fullText.isEmpty ? "" : "\n\n") + text
                                continuation.yield(.textDelta(text))
                            }

                        case "command_execution":
                            if let command = item["command"] as? String,
                               let output = item["aggregated_output"] as? String {
                                let exitCode = item["exit_code"] as? Int ?? -1
                                let formatted = "$ \(command)\n\(output)"
                                    + (exitCode != 0 ? "\n[exit code: \(exitCode)]" : "")
                                fullText += (fullText.isEmpty ? "" : "\n\n") + formatted
                                continuation.yield(.textDelta(formatted))
                            }

                        default:
                            break
                        }

                    case "turn.completed":
                        if !fullText.isEmpty {
                            continuation.yield(.textComplete(fullText))
                        }

                    default:
                        break
                    }
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        let proc = currentProcess
        currentProcess = nil
        lock.unlock()

        if let proc, proc.isRunning {
            proc.terminate()
        }
    }
}
