import Foundation

enum AgentServiceFactory {
    static func create(for type: AgentType) -> any AgentService {
        switch type {
        case .claude:
            ClaudeService()
        case .codex:
            CodexService()
        }
    }
}
