import SwiftUI

@main
struct TriviumApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    seedDefaultAgents()
                    loadChatHistory()
                    startFileWatcher()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }

    private func seedDefaultAgents() {
        guard appState.agents.isEmpty else { return }
        _ = appState.addAgent(name: "Claude", type: .claude)
        _ = appState.addAgent(name: "Codex", type: .codex)
    }

    private func loadChatHistory() {
        for (sender, text) in appState.groupChatLogger.loadExistingMessages() {
            let msgSender: MessageSender
            if sender == "User" {
                msgSender = .user
            } else if let agent = appState.agent(named: sender) {
                msgSender = .agent(agent.id)
            } else {
                msgSender = .user
            }
            appState.chatRoom.append(Message(sender: msgSender, text: text))
        }
    }

    private func startFileWatcher() {
        appState.groupChatLogger.startWatching { sender, text in
            let senderAgent = appState.agent(named: sender)
            let msgSender: MessageSender = if let senderAgent { .agent(senderAgent.id) } else { .user }
            let displayText = msgSender.isUser ? "[\(sender)] \(text)" : text
            appState.chatRoom.append(Message(sender: msgSender, text: displayText))

            // Route @mentions so mentioned agents respond
            let mentioned = InputParser.extractMentionedAgents(from: text, agents: appState.agents)
            let groupTagged = TaggedMessage(channel: .group, sender: .agent(sender), text: text)

            for agent in appState.agents where agent.id != senderAgent?.id {
                guard let coordinator = appState.coordinator(for: agent.id) else { continue }
                if mentioned.contains(agent.id) {
                    let response = coordinator.send(groupTagged, into: appState.chatRoom)
                    fanInResponse(response, from: agent.id)
                } else {
                    coordinator.injectContext(groupTagged)
                }
            }
        }
    }

    private func fanInResponse(_ message: Message, from agentID: UUID) {
        guard let agentName = appState.agent(withID: agentID)?.name else { return }
        Task {
            while message.isStreaming {
                try? await Task.sleep(for: .milliseconds(100))
            }
            appState.groupChatLogger.appendMessage(sender: agentName, text: message.text)
            let responseTagged = TaggedMessage(channel: .group, sender: .agent(agentName), text: message.text)
            for agent in appState.agents where agent.id != agentID {
                appState.coordinator(for: agent.id)?.injectContext(responseTagged)
            }
        }
    }
}
