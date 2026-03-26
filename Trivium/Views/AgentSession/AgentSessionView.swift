import SwiftUI

struct AgentSessionView: View {
    @Environment(AppState.self) private var appState
    let agent: AgentConfig
    @State private var inputText = ""

    private var conversation: Conversation {
        appState.privateConversation(for: agent.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionMessages

            Divider()

            InputBar(
                text: $inputText,
                placeholder: "Message \(agent.name)...",
                onSend: handleSend
            )
        }
        .navigationTitle(agent.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    StatusIndicator(status: agent.status)
                    Text(agent.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sessionMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conversation.messages) { message in
                        AgentMessageView(
                            message: message,
                            agentName: agent.name,
                            agentColor: agent.color
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: conversation.messages.last?.id) { _, newID in
                if let newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func handleSend(_ text: String) {
        let userMessage = Message(sender: .user, text: text)
        conversation.append(userMessage)

        // TODO: Phase 2/3 -- route through AgentCoordinator
    }
}
