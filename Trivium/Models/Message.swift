import Foundation

@Observable
@MainActor
final class Message: Identifiable {
    let id: UUID
    let sender: MessageSender
    let timestamp: Date
    var text: String
    var isStreaming: Bool
    var isError: Bool

    init(
        id: UUID = UUID(),
        sender: MessageSender,
        text: String,
        isStreaming: Bool = false,
        isError: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.isStreaming = isStreaming
        self.isError = isError
        self.timestamp = timestamp
    }
}
