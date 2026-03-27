import SwiftUI

@main
struct TriviumApp: App {
    @State private var appState: AppState

    init() {
        // Accept directory as CLI argument, default to cwd
        let dir: String
        if CommandLine.arguments.count > 1 {
            let arg = CommandLine.arguments[1]
            if arg.hasPrefix("/") {
                dir = arg
            } else {
                dir = FileManager.default.currentDirectoryPath + "/" + arg
            }
        } else {
            dir = FileManager.default.currentDirectoryPath
        }
        _appState = State(initialValue: AppState(directory: dir))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    seedDefaultAgents()
                    loadChatHistory()
                    startFileWatcher()
                }
                .navigationTitle("Trivium — \(appState.directoryName)")
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    appState.fontSize = min(appState.fontSize + 2, 32)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    appState.fontSize = max(appState.fontSize - 2, 10)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Zoom") {
                    appState.fontSize = 14
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private func seedDefaultAgents() {
        guard appState.agents.isEmpty else { return }
        _ = appState.addAgent(name: "Claude", type: .claude)
        _ = appState.addAgent(name: "Codex", type: .codex)
    }

    private func loadChatHistory() {
        for (sender, text) in appState.groupChatLogger.loadExistingMessages() {
            let msgSender: MessageSender
            let displayText: String
            if sender == "User" {
                msgSender = .user
                displayText = text
            } else if let agent = appState.agent(named: sender) {
                msgSender = .agent(agent.id)
                displayText = text
            } else {
                msgSender = .user
                displayText = "[\(sender)] \(text)"
            }
            appState.chatRoom.append(Message(sender: msgSender, text: displayText))
        }
    }

    private func startFileWatcher() {
        appState.groupChatLogger.startWatching { sender, text in
            appState.receiveExternalGroupMessage(sender: sender, text: text)
        }
    }
}
