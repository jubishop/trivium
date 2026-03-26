import Foundation

struct TaggedMessage: Sendable {
    enum Channel: Sendable {
        case privateChat
        case group
    }

    enum Sender: Sendable {
        case user
        case agent(String) // agent name
    }

    let channel: Channel
    let sender: Sender
    let text: String
    let timestamp: Date

    init(channel: Channel, sender: Sender, text: String, timestamp: Date = Date()) {
        self.channel = channel
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }

    var formatted: String {
        let tag: String
        switch (channel, sender) {
        case (.privateChat, .user):
            tag = "[Private] User"
        case (.privateChat, .agent(let name)):
            tag = "[Private] \(name)"
        case (.group, .user):
            tag = "[Group - User]"
        case (.group, .agent(let name)):
            tag = "[Group - \(name)]"
        }
        return "\(tag): \(text)"
    }
}
