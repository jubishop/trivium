import Foundation

@Observable
@MainActor
final class AppState {
    var agents: [AgentConfig] = []
    var chatRoom = Conversation()
    var privateConversations: [UUID: Conversation] = [:]

    var selectedSidebarItem: SidebarItem? = .chat

    func addAgent(name: String, type: AgentType) -> AgentConfig {
        let agent = AgentConfig(name: name, type: type)
        agents.append(agent)
        privateConversations[agent.id] = Conversation()
        return agent
    }

    func removeAgent(_ agent: AgentConfig) {
        agents.removeAll { $0.id == agent.id }
        privateConversations.removeValue(forKey: agent.id)
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
