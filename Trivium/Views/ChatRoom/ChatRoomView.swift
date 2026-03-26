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

        // TODO: Phase 4 -- parse mentions, route to agent coordinators
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
