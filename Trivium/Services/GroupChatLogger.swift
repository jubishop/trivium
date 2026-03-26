import Foundation

@MainActor
final class GroupChatLogger {
    let chatLogPath: String
    let mcpConfigPath: String
    private let mcpServerPath: String

    // File watcher state
    private var watchSource: DispatchSourceFileSystemObject?
    private var lastFileOffset: UInt64 = 0
    private var onNewMessage: ((String, String) -> Void)? // (sender, text)

    init() {
        let tmpDir = NSTemporaryDirectory() + "trivium/"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        chatLogPath = tmpDir + "group-chat.jsonl"
        mcpConfigPath = tmpDir + "mcp-config.json"

        let bundlePath = Bundle.main.bundlePath
        let appDir = (bundlePath as NSString).deletingLastPathComponent
        let candidates = [
            appDir + "/trivium-mcp-server",
            NSHomeDirectory() + "/Desktop/trivium/trivium-mcp-server",
        ]
        mcpServerPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates.last!

        writeMCPConfig()
    }

    func appendMessage(sender: String, text: String) {
        let entry: [String: Any] = [
            "sender": sender,
            "text": text,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let lineData = (line + "\n").data(using: .utf8)!

        let fd = open(chatLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        lineData.withUnsafeBytes { buf in
            _ = write(fd, buf.baseAddress!, buf.count)
        }
        close(fd)
    }

    // Load all existing messages from the JSONL file.
    // Returns (sender, text) tuples for each line.
    func loadExistingMessages() -> [(sender: String, text: String)] {
        guard let data = try? String(contentsOfFile: chatLogPath, encoding: .utf8) else {
            return []
        }
        let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.compactMap { line in
            guard let jsonData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let sender = entry["sender"] as? String,
                  let text = entry["text"] as? String else { return nil }
            return (sender, text)
        }
    }

    // Start watching the JSONL file for new lines written by external processes
    // (e.g., agents using send_to_group_chat via the MCP server).
    // The callback fires on MainActor for each new message not written by us.
    func startWatching(onNewMessage: @escaping (String, String) -> Void) {
        self.onNewMessage = onNewMessage

        // Ensure the file exists
        if !FileManager.default.fileExists(atPath: chatLogPath) {
            FileManager.default.createFile(atPath: chatLogPath, contents: nil)
        }

        // Start watching from current EOF -- existing messages are loaded separately
        if let attrs = try? FileManager.default.attributesOfItem(atPath: chatLogPath),
           let size = attrs[.size] as? UInt64 {
            lastFileOffset = size
        }

        let fd = open(chatLogPath, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            self?.readNewLines()
        }

        source.setCancelHandler {
            close(fd)
        }

        watchSource = source
        source.resume()
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }

    func clearLog() {
        try? "".write(toFile: chatLogPath, atomically: true, encoding: .utf8)
        lastFileOffset = 0
    }

    private func readNewLines() {
        let fd = open(chatLogPath, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Seek to where we left off
        lseek(fd, Int64(lastFileOffset), SEEK_SET)

        let bufferSize = 8192
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(fd, buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }

        lastFileOffset += UInt64(data.count)

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let sender = entry["sender"] as? String,
                  let msgText = entry["text"] as? String else { continue }

            // Skip messages we wrote ourselves (User or known agent names from the app)
            // The MCP server writes with sender "agent" -- those are the external ones
            if sender == "agent" || sender.hasPrefix("agent:") {
                DispatchQueue.main.async { [weak self] in
                    self?.onNewMessage?(sender, msgText)
                }
            }
        }
    }

    private func writeMCPConfig() {
        let config: [String: Any] = [
            "mcpServers": [
                "trivium-group-chat": [
                    "command": mcpServerPath,
                    "args": [chatLogPath],
                ],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: mcpConfigPath))
    }
}
