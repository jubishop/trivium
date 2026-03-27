import Foundation

enum StreamEvent: Sendable {
    case sessionStarted(id: String)
    case textDelta(String)
    case textComplete(String)
    case toolUseStarted(id: String, name: String)
    case permissionRequested(id: String, toolName: String, toolInput: String)
    case error(String)
    case done
}

protocol AgentService: Sendable {
    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent>
    func respondToPermission(requestID: String, granted: Bool)
    func cancel()
}

final class ProcessStreamCoordinator: @unchecked Sendable {
    private let label: String
    private let continuation: AsyncStream<StreamEvent>.Continuation
    private let lock = NSLock()

    private var stdoutFinished = false
    private var stderrFinished = false
    private var terminationStatus: Int32?
    private var stderrText = ""
    private var hasFinished = false

    init(label: String, continuation: AsyncStream<StreamEvent>.Continuation) {
        self.label = label
        self.continuation = continuation
    }

    func appendStderrLine(_ line: String) {
        lock.lock()
        if !stderrText.isEmpty {
            stderrText += "\n"
        }
        stderrText += line
        lock.unlock()
    }

    func markStdoutFinished() {
        lock.lock()
        stdoutFinished = true
        lock.unlock()
        finishIfReady()
    }

    func markStderrFinished() {
        lock.lock()
        stderrFinished = true
        lock.unlock()
        finishIfReady()
    }

    func markTerminated(status: Int32) {
        lock.lock()
        terminationStatus = status
        lock.unlock()
        finishIfReady()
    }

    private func finishIfReady() {
        let completion: (Int32, String)?

        lock.lock()
        if hasFinished || !stdoutFinished || !stderrFinished || terminationStatus == nil {
            completion = nil
        } else {
            hasFinished = true
            completion = (terminationStatus ?? 0, stderrText)
        }
        lock.unlock()

        guard let (status, stderr) = completion else { return }

        if status != 0 {
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Log.error("[\(label)] stderr: \(trimmed)")
                continuation.yield(.error(trimmed))
            } else {
                continuation.yield(.error("Process exited with code \(status)"))
            }
        }

        continuation.yield(.done)
        continuation.finish()
    }
}
