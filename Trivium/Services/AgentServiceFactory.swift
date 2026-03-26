import Foundation

enum AgentServiceFactory {
    static func create(for type: AgentType) -> any AgentService {
        switch type {
        case .claude:
            ClaudeService()
        case .codex:
            // TODO: Phase 3
            ClaudeService() // placeholder
        }
    }
}
