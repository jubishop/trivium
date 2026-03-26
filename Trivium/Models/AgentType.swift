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

    var defaultWorkingDirectory: String {
        NSHomeDirectory() + "/Desktop/trivium"
    }

    func cliArgs(logger: GroupChatLogger?) -> [String] {
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

    // Build environment with the paths both CLIs need
    static var terminalEnvironment: [String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            NSHomeDirectory() + "/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }
}
