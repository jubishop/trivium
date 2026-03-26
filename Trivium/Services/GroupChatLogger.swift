import Foundation

@MainActor
final class GroupChatLogger {
    let directory: String
    let chatLogPath: String

    private var watchSource: (any DispatchSourceFileSystemObject)?
    private var lastFileOffset: UInt64 = 0
    private var onNewMessage: ((String, String) -> Void)?
    private var recentAppWrites: Set<String> = []

    init(directory: String) {
        self.directory = (directory as NSString).standardizingPath
        let logDir = Self.chatLogDir(for: self.directory)
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        chatLogPath = logDir + "/group-chat.jsonl"
    }

    static func chatLogDir(for directory: String) -> String {
        let normalized = (directory as NSString).standardizingPath
        let hashValue = normalized.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = hash &* 33 &+ UInt64(byte)
        }
        return "/tmp/trivium/chats/\(String(hashValue, radix: 16))"
    }

    func appendMessage(sender: String, text: String) {
        let entry: [String: Any] = [
            "sender": sender,
            "text": text,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        recentAppWrites.insert(line)

        let lineData = Data((line + "\n").utf8)
        if !FileManager.default.fileExists(atPath: chatLogPath) {
            FileManager.default.createFile(atPath: chatLogPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: chatLogPath) else { return }
        handle.seekToEndOfFile()
        handle.write(lineData)
        try? handle.close()
    }

    func loadExistingMessages() -> [(sender: String, text: String)] {
        guard let data = try? String(contentsOfFile: chatLogPath, encoding: .utf8) else {
            return []
        }
        return data.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { parseLine($0) }
    }

    func startWatching(onNewMessage: @escaping (String, String) -> Void) {
        self.onNewMessage = onNewMessage

        if !FileManager.default.fileExists(atPath: chatLogPath) {
            FileManager.default.createFile(atPath: chatLogPath, contents: nil)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: chatLogPath),
           let size = attrs[.size] as? UInt64 {
            lastFileOffset = size
        }

        guard let handle = FileHandle(forReadingAtPath: chatLogPath) else { return }
        let fd = handle.fileDescriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.readNewLines()
            }
        }

        source.setCancelHandler {
            try? handle.close()
        }

        watchSource = source
        source.resume()
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }

    private func readNewLines() {
        guard let handle = FileHandle(forReadingAtPath: chatLogPath) else { return }
        handle.seek(toFileOffset: lastFileOffset)
        let data = handle.readDataToEndOfFile()
        try? handle.close()

        lastFileOffset += UInt64(data.count)

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            if recentAppWrites.remove(line) != nil { continue }
            guard let (sender, msgText) = parseLine(line) else { continue }
            onNewMessage?(sender, msgText)
        }
    }

    private func parseLine(_ line: String) -> (sender: String, text: String)? {
        guard let jsonData = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let sender = entry["sender"] as? String,
              let text = entry["text"] as? String else { return nil }
        return (sender, text)
    }
}
