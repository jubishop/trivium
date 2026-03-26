import SwiftUI

struct AgentSessionView: View {
    @Environment(AppState.self) private var appState
    let agent: AgentConfig
    var isActive: Bool = true
    @State private var processEnded = false
    @State private var exitCode: Int32? = nil

    var body: some View {
        ZStack {
            if processEnded {
                ContentUnavailableView(
                    "\(agent.name) session ended",
                    systemImage: "terminal",
                    description: Text(verbatim: "Exit code: \(exitCode.map(String.init) ?? "unknown")\nExecutable: \(agent.type.executablePath)\nArgs: \(agent.type.cliArgs(logger: appState.groupChatLogger))\nCwd: \(agent.type.defaultWorkingDirectory)")
                )
            } else {
                TerminalViewRepresentable(
                    executable: agent.type.executablePath,
                    args: agent.type.cliArgs(logger: appState.groupChatLogger),
                    environment: AgentType.terminalEnvironment,
                    workingDirectory: agent.type.defaultWorkingDirectory,
                    isActive: isActive,
                    onProcessTerminated: { code in
                        Task { @MainActor in
                            exitCode = code
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
