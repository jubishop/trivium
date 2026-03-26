import Foundation

enum MessageSender: Sendable, Equatable {
    case user
    case agent(UUID)

    var isUser: Bool {
        if case .user = self { return true }
        return false
    }
}
