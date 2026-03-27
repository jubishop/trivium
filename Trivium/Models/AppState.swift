import Foundation

@Observable
@MainActor
final class AppState {
    private enum GroupResponseMode {
        case allIfNoMentions
        case mentionedOnly
    }

    let directory: String
    var agents: [AgentConfig] = []
    var coordinators: [UUID: AgentCoordinator] = [:]
    var chatRoom = Conversation()
    var fontSize: CGFloat = 14
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

    func sendUserChatMessage(_ text: String) {
        chatRoom.append(Message(sender: .user, text: text))
        groupChatLogger.appendMessage(sender: "User", text: text)

        let tagged = TaggedMessage(channel: .group, sender: .user, text: text)
        let mentionedIDs = Set(InputParser.extractMentionedAgents(from: text, agents: agents))
        route(tagged, excluding: nil, mentionedIDs: mentionedIDs, responseMode: .allIfNoMentions)
    }

    func receiveExternalGroupMessage(sender senderName: String, text: String) {
        let senderAgent = agent(named: senderName)
        let senderKind: MessageSender = if let senderAgent { .agent(senderAgent.id) } else { .user }
        let displayText = senderKind.isUser && senderName != "User" ? "[\(senderName)] \(text)" : text
        chatRoom.append(Message(sender: senderKind, text: displayText))

        let taggedSender: TaggedMessage.Sender = senderName == "User" ? .user : .agent(senderName)
        let tagged = TaggedMessage(channel: .group, sender: taggedSender, text: text)
        let mentionedIDs = Set(InputParser.extractMentionedAgents(from: text, agents: agents))
        route(tagged, excluding: senderAgent?.id, mentionedIDs: mentionedIDs, responseMode: .mentionedOnly)
    }

    func handleCompletedAgentResponse(_ message: Message, from agentID: UUID) {
        guard let agent = agent(withID: agentID) else { return }

        groupChatLogger.appendMessage(sender: agent.name, text: message.text)

        let tagged = TaggedMessage(channel: .group, sender: .agent(agent.name), text: message.text)
        let mentionedIDs = Set(InputParser.extractMentionedAgents(from: message.text, agents: agents))
            .subtracting([agentID])
        route(tagged, excluding: agentID, mentionedIDs: mentionedIDs, responseMode: .mentionedOnly)
    }

    var directoryName: String {
        (directory as NSString).lastPathComponent
    }

    private func route(
        _ tagged: TaggedMessage,
        excluding senderAgentID: UUID?,
        mentionedIDs: Set<UUID>,
        responseMode: GroupResponseMode
    ) {
        let respondingIDs: Set<UUID>
        switch responseMode {
        case .allIfNoMentions:
            respondingIDs = mentionedIDs.isEmpty ? Set(agents.map(\.id)) : mentionedIDs
        case .mentionedOnly:
            respondingIDs = mentionedIDs
        }

        for agent in agents where agent.id != senderAgentID {
            guard let coordinator = coordinator(for: agent.id) else { continue }

            if respondingIDs.contains(agent.id) {
                let responseMessage = coordinator.send(tagged, into: chatRoom)
                observeAgentResponse(responseMessage, from: agent.id)
            } else {
                coordinator.injectContext(tagged)
            }
        }
    }

    private func observeAgentResponse(_ message: Message, from agentID: UUID) {
        Task { [weak self] in
            guard let self else { return }

            while message.isStreaming {
                try? await Task.sleep(for: .milliseconds(100))
            }

            self.handleCompletedAgentResponse(message, from: agentID)
        }
    }
}
