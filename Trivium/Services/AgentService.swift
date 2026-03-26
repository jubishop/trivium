import Foundation

enum StreamEvent: Sendable {
    case sessionStarted(id: String)
    case textDelta(String)
    case textComplete(String)
    case error(String)
    case done
}

protocol AgentService: Sendable {
    func send(prompt: String, sessionID: String?, workingDirectory: String) -> AsyncStream<StreamEvent>
    func cancel()
}
