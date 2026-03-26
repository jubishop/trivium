import Foundation

@Observable
@MainActor
final class AppState {
    let directory: String
    var agents: [AgentConfig] = []
    var coordinators: [UUID: AgentCoordinator] = [:]
    var chatRoom = Conversation()
    let groupChatLogger: GroupChatLogger

    init(directory: String) {
        self.directory = directory
        self.groupChatLogger = GroupChatLogger(directory: directory)
    }

    func addAgent(name: String, type: AgentType) -> AgentConfig {
        let agent = AgentConfig(name: name, type: type)
        agents.append(agent)
        let coordinator = AgentCoordinator(config: agent)
        coordinator.workingDirectory = directory
        coordinator.loadSessionID()
        coordinators[agent.id] = coordinator
        return agent
    }

    func removeAgent(_ agent: AgentConfig) {
        coordinators[agent.id]?.cancel()
        coordinators.removeValue(forKey: agent.id)
        agents.removeAll { $0.id == agent.id }
    }

    func coordinator(for agentID: UUID) -> AgentCoordinator? {
        coordinators[agentID]
    }

    func agent(named name: String) -> AgentConfig? {
        agents.first { $0.name.lowercased() == name.lowercased() }
    }

    func agent(withID id: UUID) -> AgentConfig? {
        agents.first { $0.id == id }
    }

    var directoryName: String {
        (directory as NSString).lastPathComponent
    }
}
