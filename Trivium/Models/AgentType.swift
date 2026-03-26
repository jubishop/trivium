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

    // Environment with the paths both CLIs need
    static var processEnvironment: [String: String] {
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
        return env
    }
}
