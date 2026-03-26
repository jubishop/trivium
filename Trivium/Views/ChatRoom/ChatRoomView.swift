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
        let userMessage = Message(sender: .user, text: text)
        appState.chatRoom.append(userMessage)
        appState.groupChatLogger.appendMessage(sender: "User", text: text)

        let parsed = InputParser.parse(text, agents: appState.agents)

        switch parsed {
        case .chat(let chatText, let mentionedIDs):
            let groupMessage = TaggedMessage(channel: .group, sender: .user, text: chatText)

            // Determine who responds vs who just observes
            let respondingIDs = Set(mentionedIDs.isEmpty ? appState.agents.map(\.id) : mentionedIDs)

            for agent in appState.agents {
                guard let coordinator = appState.coordinator(for: agent.id) else { continue }

                if respondingIDs.contains(agent.id) {
                    // send() appends the tagged message to history AND prompts a response
                    let responseMessage = coordinator.send(groupMessage, into: appState.chatRoom)
                    fanInResponse(responseMessage, from: agent.id)
                } else {
                    // Just record in context, no response
                    coordinator.injectContext(groupMessage)
                }
            }

        case .shellCommand(let command):
            runShellCommand(command)
        }
    }

    private func fanInResponse(_ message: Message, from agentID: UUID) {
        guard let agentName = appState.agent(withID: agentID)?.name else { return }

        Task {
            // Wait for streaming to complete
            while message.isStreaming {
                try? await Task.sleep(for: .milliseconds(100))
            }

            let responseTagged = TaggedMessage(
                channel: .group,
                sender: .agent(agentName),
                text: message.text
            )

            // Log to file for MCP access
            appState.groupChatLogger.appendMessage(sender: agentName, text: message.text)

            // Inject into all OTHER agents
            for agent in appState.agents where agent.id != agentID {
                appState.coordinator(for: agent.id)?.injectContext(responseTagged)
            }
        }
    }

    private func runShellCommand(_ command: String) {
        let shellMsg = Message(sender: .user, text: "$ \(command)")
        appState.chatRoom.append(shellMsg)

        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                let errMsg = Message(sender: .user, text: "[Shell error: \(error.localizedDescription)]")
                appState.chatRoom.append(errMsg)
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !output.isEmpty {
                let resultMsg = Message(sender: .user, text: "```\n\(output)\n```")
                appState.chatRoom.append(resultMsg)
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
