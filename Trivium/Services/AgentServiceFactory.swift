import Foundation

enum AgentServiceFactory {
    static func create(for type: AgentType) -> any AgentService {
        switch type {
        case .claude:
            ClaudeService(executablePath: type.executablePath)
        case .codex:
            CodexService(executablePath: type.executablePath)
        }
    }
}
