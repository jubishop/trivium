import Foundation
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

    var executablePath: String? {
        let candidates = ([ProcessInfo.processInfo.environment[overrideEnvironmentKey]] + preferredExecutablePaths + pathExecutableCandidates)
            .compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // Environment with the paths both CLIs need
    static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            NSHomeDirectory() + "/.local/bin",
            NSHomeDirectory() + "/.cargo/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }

    var executableLookupHint: String {
        switch self {
        case .claude:
            "Set TRIVIUM_CLAUDE_PATH or install `claude` on your PATH."
        case .codex:
            "Set TRIVIUM_CODEX_PATH or install `codex` on your PATH."
        }
    }

    private var overrideEnvironmentKey: String {
        switch self {
        case .claude: "TRIVIUM_CLAUDE_PATH"
        case .codex: "TRIVIUM_CODEX_PATH"
        }
    }

    private var executableName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    private var preferredExecutablePaths: [String] {
        switch self {
        case .claude:
            [
                NSHomeDirectory() + "/.local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
            ]
        case .codex:
            [
                "/opt/homebrew/bin/codex",
                NSHomeDirectory() + "/.cargo/bin/codex",
                NSHomeDirectory() + "/.local/bin/codex",
                "/usr/local/bin/codex",
            ]
        }
    }

    private var pathExecutableCandidates: [String] {
        let path = AgentType.processEnvironment["PATH"] ?? ""
        return path.split(separator: ":").map { "\($0)/\(executableName)" }
    }
}
