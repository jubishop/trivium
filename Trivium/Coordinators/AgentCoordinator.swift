import Foundation

@Observable
@MainActor
final class AgentCoordinator {
    let config: AgentConfig
    private let service: any AgentService
    private(set) var sessionID: String?
    private(set) var fullHistory: [TaggedMessage] = []
    private var currentTask: Task<Void, Never>?

    var workingDirectory: String = NSHomeDirectory() + "/Desktop/trivium"

    init(config: AgentConfig) {
        self.config = config
        self.service = AgentServiceFactory.create(for: config.type)
    }

    // Record a message in this agent's context without prompting a response.
    // Used for group messages from other participants that this agent should see
    // but not respond to.
    func injectContext(_ tagged: TaggedMessage) {
        fullHistory.append(tagged)
    }

    // Send a message and get a streaming response.
    // The tagged message is appended to history, then forwarded to the CLI.
    // Returns the response Message object which will be mutated as text streams in.
    @discardableResult
    func send(_ tagged: TaggedMessage, into conversation: Conversation) -> Message {
        cancel()

        fullHistory.append(tagged)

        let responseMessage = Message(
            sender: .agent(config.id),
            text: "",
            isStreaming: true
        )
        conversation.append(responseMessage)
        config.status = .processing

        let prompt = buildPrompt(for: tagged)

        currentTask = Task { [weak self] in
            guard let self else { return }

            var receivedText = false
            let stream = service.send(
                prompt: prompt,
                sessionID: sessionID,
                workingDirectory: workingDirectory
            )

            for await event in stream {
                guard !Task.isCancelled else { break }

                switch event {
                case .sessionStarted(let id):
                    self.sessionID = id
                    self.saveSessionID()

                case .textDelta(let delta):
                    responseMessage.text += delta
                    receivedText = true

                case .textComplete(let full):
                    if !receivedText {
                        responseMessage.text = full
                    }

                case .error(let err):
                    if responseMessage.text.isEmpty {
                        responseMessage.text = err
                    } else {
                        responseMessage.text += "\n\n[Error: \(err)]"
                    }
                    responseMessage.isError = true

                case .done:
                    break
                }
            }

            responseMessage.isStreaming = false
            config.status = .idle

            // Record the agent's response in history
            let responseTagged = TaggedMessage(
                channel: tagged.channel,
                sender: .agent(config.name),
                text: responseMessage.text
            )
            fullHistory.append(responseTagged)
        }

        return responseMessage
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        service.cancel()
    }

    private func buildPrompt(for tagged: TaggedMessage) -> String {
        // For first message, include the identity preamble
        if sessionID == nil {
            let preamble = identityPreamble()
            return "\(preamble)\n\n\(tagged.formatted)"
        }

        // For continued sessions, just send the new tagged message
        return tagged.formatted
    }

    private func identityPreamble() -> String {
        """
        You are "\(config.name)". You are in a multi-agent chat app called Trivium. \
        Messages tagged [Private] are between you and the user only. \
        Messages tagged [Group - <name>] are from the group chat visible to all participants. \
        When responding in the group chat, use @name to address other participants. \
        Respond naturally and concisely.
        """
    }

    // MARK: - Session persistence

    private var sessionFilePath: String {
        // Store alongside the chat log, keyed by agent name
        let dir = (GroupChatLogger.chatLogDir(for: workingDirectory))
        return dir + "/session-\(config.name.lowercased()).id"
    }

    private func saveSessionID() {
        guard let sessionID else { return }
        try? sessionID.write(toFile: sessionFilePath, atomically: true, encoding: .utf8)
        Log.info("[\(config.name)] Saved session ID: \(sessionID)")
    }

    func loadSessionID() {
        guard let saved = try? String(contentsOfFile: sessionFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !saved.isEmpty else { return }
        sessionID = saved
        Log.info("[\(config.name)] Restored session ID: \(saved)")
    }
}
