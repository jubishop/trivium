import SwiftUI

struct AgentSessionView: View {
    @Environment(AppState.self) private var appState
    let agent: AgentConfig
    var isActive: Bool = true
    @State private var processEnded = false

    var body: some View {
        ZStack {
            if processEnded {
                ContentUnavailableView(
                    "\(agent.name) session ended",
                    systemImage: "terminal",
                    description: Text("The process has terminated. Remove and re-add the agent to start a new session.")
                )
            } else {
                TerminalViewRepresentable(
                    executable: agent.type.executablePath,
                    args: agent.type.interactiveArgs(logger: appState.groupChatLogger),
                    environment: nil,
                    workingDirectory: NSHomeDirectory(),
                    isActive: isActive,
                    onProcessTerminated: { _ in
                        Task { @MainActor in
                            processEnded = true
                            agent.status = .disconnected
                        }
                    }
                )
            }
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
        .onAppear {
            agent.status = .idle
        }
    }
}
