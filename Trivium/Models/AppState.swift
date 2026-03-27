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
    let permissionFileWatcher: PermissionFileWatcher
    var pendingPermissions: [PermissionRequest] = []

    init(directory: String) {
        self.directory = directory
        self.groupChatLogger = GroupChatLogger(directory: directory)
        self.permissionFileWatcher = PermissionFileWatcher(directory: directory)
    }

    func addAgent(name: String, type: AgentType) -> AgentConfig {
        let agent = AgentConfig(name: name, type: type)
        agents.append(agent)
        let coordinator = AgentCoordinator(config: agent)
        coordinator.workingDirectory = directory
        coordinator.loadSessionID()

        // Set up permissions dir for Claude's hook
        if let claudeService = coordinator.service as? ClaudeService {
            claudeService.permissionsDir = permissionFileWatcher.permissionsDir
        }

        // Wire permission requests from both agent types to AppState
        coordinator.onPermissionRequest = { [weak self] request in
            self?.receivePermissionRequest(request)
        }

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

    // MARK: - Permissions

    func receivePermissionRequest(_ request: PermissionRequest) {
        pendingPermissions.append(request)
    }

    func approvePermission(_ id: String) {
        guard let request = pendingPermissions.first(where: { $0.id == id }) else { return }
        request.status = .approved
        pendingPermissions.removeAll { $0.id == id }

        let agentConfig = agent(withID: request.agentID)
        agentConfig?.status = .processing

        // Route the response to the correct mechanism
        if let coordinator = coordinator(for: request.agentID) {
            if coordinator.config.type == .claude {
                // Claude uses file-based IPC
                permissionFileWatcher.writeResponse(id: id, granted: true)
            } else {
                // Codex uses JSON-RPC via stdin
                coordinator.service.respondToPermission(requestID: id, granted: true)
            }
        }
    }

    func denyPermission(_ id: String) {
        guard let request = pendingPermissions.first(where: { $0.id == id }) else { return }
        request.status = .denied
        pendingPermissions.removeAll { $0.id == id }

        let agentConfig = agent(withID: request.agentID)
        agentConfig?.status = .processing

        if let coordinator = coordinator(for: request.agentID) {
            if coordinator.config.type == .claude {
                permissionFileWatcher.writeResponse(id: id, granted: false)
            } else {
                coordinator.service.respondToPermission(requestID: id, granted: false)
            }
        }
    }

    func startPermissionFileWatcher() {
        permissionFileWatcher.startWatching { [weak self] id, toolName, toolInput, _ in
            guard let self else { return }
            // Find which Claude agent this is for (use the first Claude agent)
            let claudeAgent = self.agents.first { $0.type == .claude }
            let agentID = claudeAgent?.id ?? UUID()
            let request = PermissionRequest(
                id: id,
                agentID: agentID,
                toolName: toolName,
                toolInput: toolInput
            )
            self.receivePermissionRequest(request)
        }
    }

    func pendingPermission(for agentID: UUID) -> PermissionRequest? {
        pendingPermissions.first { $0.agentID == agentID }
    }
}
