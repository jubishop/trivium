import Foundation
import SwiftUI

@Observable
@MainActor
final class AgentConfig: Identifiable {
    let id: UUID
    var name: String
    let type: AgentType
    var status: AgentStatus = .idle

    init(id: UUID = UUID(), name: String, type: AgentType) {
        self.id = id
        self.name = name
        self.type = type
    }

    var color: Color { type.color }
    var icon: String { type.icon }

    var mentionHandle: String { "@\(name)" }
}
