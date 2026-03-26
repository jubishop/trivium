enum AgentStatus: Sendable {
    case disconnected
    case idle
    case processing
    case error(String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}
