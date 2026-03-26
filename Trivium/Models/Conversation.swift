import Foundation

@Observable
@MainActor
final class Conversation {
    var messages: [Message] = []

    func append(_ message: Message) {
        messages.append(message)
    }
}
