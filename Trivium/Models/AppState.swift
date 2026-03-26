import Foundation

@Observable
@MainActor
final class AppState {
    var agents: [AgentConfig] = []
    var coordinators: [UUID: AgentCoordinator] = [:]
    var chatRoom = Conversation()
    var privateConversations: [UUID: Conversation] = [:]

    var selectedSidebarItem: SidebarItem? = .chat

    let groupChatLogger = GroupChatLogger()

    func addAgent(name: String, type: AgentType) -> AgentConfig {
        let agent = AgentConfig(name: name, type: type)
        agents.append(agent)
        privateConversations[agent.id] = Conversation()
        coordinators[agent.id] = AgentCoordinator(config: agent)
        return agent
    }

    func removeAgent(_ agent: AgentConfig) {
        coordinators[agent.id]?.cancel()
        coordinators.removeValue(forKey: agent.id)
        agents.removeAll { $0.id == agent.id }
        privateConversations.removeValue(forKey: agent.id)
    }

    func coordinator(for agentID: UUID) -> AgentCoordinator? {
        coordinators[agentID]
    }

    func privateConversation(for agentID: UUID) -> Conversation {
        if let existing = privateConversations[agentID] {
            return existing
        }
        let conv = Conversation()
        privateConversations[agentID] = conv
        return conv
    }

    func agent(named name: String) -> AgentConfig? {
        agents.first { $0.name.lowercased() == name.lowercased() }
    }

    func agent(withID id: UUID) -> AgentConfig? {
        agents.first { $0.id == id }
    }
}

enum SidebarItem: Hashable {
    case chat
    case agent(UUID)
}
