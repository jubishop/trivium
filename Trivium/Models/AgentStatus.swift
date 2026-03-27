enum AgentStatus: Sendable {
    case disconnected
    case idle
    case processing
    case awaitingPermission
    case error(String)

    var isProcessing: Bool {
        if case .processing = self { return true }
        if case .awaitingPermission = self { return true }
        return false
    }
}
