import SwiftUI

struct ChatMessageBubble: View {
    let message: Message
    let agentName: String?
    let agentColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.sender.isUser {
                Spacer(minLength: 60)
                userBubble
            } else {
                agentBubble
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("You")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(message.text)
                .padding(10)
                .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
        }
    }

    private var agentBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(agentColor)
                    .frame(width: 8, height: 8)

                Text(agentName ?? "Agent")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if message.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            Text(message.text.isEmpty && message.isStreaming ? "..." : message.text)
                .padding(10)
                .background(agentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
                .foregroundStyle(message.isError ? .red : .primary)
        }
    }
}
