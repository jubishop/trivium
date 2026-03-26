import Foundation

final class ClaudeService: AgentService, @unchecked Sendable {
    private static let binaryPath = "/Users/jubi/.local/bin/claude"

    private var currentProcess: Process?
    private let lock = NSLock()

    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent> {
        cancel()

        return AsyncStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.binaryPath)
            process.environment = AgentType.processEnvironment

            var args = [
                "-p",
                "--output-format", "stream-json",
                "--verbose",
                "--include-partial-messages",
            ]

            if let sessionID {
                args.append(contentsOf: ["-c", "--session-id", sessionID])
            }

            args.append(prompt)

            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            lock.lock()
            currentProcess = process
            lock.unlock()

            var capturedSessionID: String?
            var fullText = ""

            process.terminationHandler = { [weak self] proc in
                if proc.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "Process exited with code \(proc.terminationStatus)"
                    if !errStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.yield(.error(errStr))
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
                            continuation.yield(.sessionStarted(id: sid))
                        }

                    case "stream_event":
                        guard let event = json["event"] as? [String: Any],
                              let eventType = event["type"] as? String else { continue }

                        if eventType == "content_block_delta",
                           let delta = event["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String, deltaType == "text_delta",
                           let text = delta["text"] as? String {
                            fullText += text
                            continuation.yield(.textDelta(text))
                        }

                    case "result":
                        if let result = json["result"] as? String {
                            continuation.yield(.textComplete(result))
                        }
                        if let sid = json["session_id"] as? String, capturedSessionID == nil {
                            capturedSessionID = sid
                            continuation.yield(.sessionStarted(id: sid))
                        }
                        if let isError = json["is_error"] as? Bool, isError,
                           let errMsg = json["result"] as? String {
                            continuation.yield(.error(errMsg))
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
