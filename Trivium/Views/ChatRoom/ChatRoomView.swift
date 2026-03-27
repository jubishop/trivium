import SwiftUI

struct ChatRoomView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            chatMessages

            Divider()

            InputBar(
                text: $inputText,
                placeholder: mentionHint,
                onSend: handleSend
            )
        }
        .navigationTitle("Chat")
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.chatRoom.messages) { message in
                        ChatMessageBubble(
                            message: message,
                            agentName: agentName(for: message.sender),
                            agentColor: agentColor(for: message.sender)
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: appState.chatRoom.messages.last?.id) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var mentionHint: String {
        let names = appState.agents.map { "@\($0.name)" }.joined(separator: " ")
        return "Message \(names)"
    }

    private func handleSend(_ text: String) {
        let parsed = InputParser.parse(text, agents: appState.agents)

        switch parsed {
        case .chat(let chatText, _):
            appState.sendUserChatMessage(chatText)
        case .shellCommand(let command):
            runShellCommand(command)
        }
    }

    private func runShellCommand(_ command: String) {
        appState.chatRoom.append(Message(sender: .user, text: "$ \(command)"))

        let workingDirectory = appState.directory

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let exitCode = process.terminationStatus

                await MainActor.run {
                    if !output.isEmpty {
                        appState.chatRoom.append(Message(sender: .user, text: "```\n\(output)\n```"))
                    } else if exitCode != 0 {
                        appState.chatRoom.append(Message(sender: .user, text: "[Shell exited with status \(exitCode)]"))
                    }
                }
            } catch {
                await MainActor.run {
                    appState.chatRoom.append(
                        Message(sender: .user, text: "[Shell error: \(error.localizedDescription)]")
                    )
                }
                return
            }
        }
    }

    private func agentName(for sender: MessageSender) -> String? {
        switch sender {
        case .user: nil
        case .agent(let id): appState.agent(withID: id)?.name
        }
    }

    private func agentColor(for sender: MessageSender) -> Color {
        switch sender {
        case .user: .blue
        case .agent(let id): appState.agent(withID: id)?.color ?? .gray
        }
    }
}
