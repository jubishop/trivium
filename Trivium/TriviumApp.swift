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
        .defaultSize(width: 1000, height: 700)
    }

    private func seedDefaultAgents() {
        guard appState.agents.isEmpty else { return }
        _ = appState.addAgent(name: "Claude", type: .claude)
        _ = appState.addAgent(name: "Codex", type: .codex)
    }

    private func loadChatHistory() {
        let existing = appState.groupChatLogger.loadExistingMessages()
        for (sender, text) in existing {
            let msgSender: MessageSender
            if sender == "User" {
                msgSender = .user
            } else if let agent = appState.agent(named: sender) {
                msgSender = .agent(agent.id)
            } else {
                // External agent or unknown sender
                msgSender = .user
            }
            let message = Message(sender: msgSender, text: sender == "User" ? text : text)
            appState.chatRoom.append(message)
        }
    }

    private func startFileWatcher() {
        appState.groupChatLogger.startWatching { sender, text in
            // Message from an agent via MCP send_to_group_chat
            let msgSender: MessageSender
            if let agent = appState.agent(named: sender) {
                msgSender = .agent(agent.id)
            } else {
                // Unknown sender -- show with name prefix
                msgSender = .user
            }
            let message = Message(sender: msgSender, text: msgSender.isUser ? "[\(sender)] \(text)" : text)
            appState.chatRoom.append(message)
        }
    }
}
