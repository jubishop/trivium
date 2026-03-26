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
}
