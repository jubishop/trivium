import SwiftUI

enum AgentType: String, Sendable, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var color: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        }
    }

    var icon: String {
        switch self {
        case .claude: "brain.head.profile"
        case .codex: "terminal"
        }
    }

    var executablePath: String {
        switch self {
        case .claude: "/Users/jubi/.local/bin/claude"
        case .codex: "/opt/homebrew/bin/codex"
        }
    }

    func interactiveArgs(logger: GroupChatLogger?) -> [String] {
        switch self {
        case .claude:
            var args: [String] = []
            if let logger {
                args.append(contentsOf: ["--mcp-config", logger.mcpConfigPath])
            }
            return args
        case .codex:
            var args = ["--full-auto"]
            if let logger {
                let serverPath = NSHomeDirectory() + "/Desktop/trivium/trivium-mcp-server"
                args.append(contentsOf: [
                    "-c", "mcp_servers.trivium-group-chat.command=\"\(serverPath)\"",
                    "-c", "mcp_servers.trivium-group-chat.args=[\"\(logger.chatLogPath)\"]",
                ])
            }
            return args
        }
    }
}
