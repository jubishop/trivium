import Foundation

enum ParsedInput {
    case chat(text: String, mentionedAgentIDs: [UUID])
    case shellCommand(String)
}

@MainActor
enum InputParser {
    static func parse(_ raw: String, agents: [AgentConfig]) -> ParsedInput {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("$") {
            return .shellCommand(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }

        let mentioned = extractMentionedAgents(from: trimmed, agents: agents)
        return .chat(text: trimmed, mentionedAgentIDs: mentioned)
    }

    static func extractMentionedAgents(from text: String, agents: [AgentConfig]) -> [UUID] {
        let lower = text.lowercased()
        var mentioned: [UUID] = []

        for agent in agents {
            let handle = "@\(agent.name.lowercased())"
            if lower.contains(handle) {
                mentioned.append(agent.id)
            }
        }

        // @all or @everyone mentions all agents
        if lower.contains("@all") || lower.contains("@everyone") {
            return agents.map(\.id)
        }

        return mentioned
    }
}
