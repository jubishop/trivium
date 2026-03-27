import Foundation

@Observable
@MainActor
final class PermissionRequest: Identifiable {
    let id: String
    let agentID: UUID
    let toolName: String
    let toolInput: String
    let timestamp: Date
    var status: Status = .pending

    enum Status {
        case pending
        case approved
        case denied
    }

    init(id: String, agentID: UUID, toolName: String, toolInput: String, timestamp: Date = Date()) {
        self.id = id
        self.agentID = agentID
        self.toolName = toolName
        self.toolInput = toolInput
        self.timestamp = timestamp
    }
}
