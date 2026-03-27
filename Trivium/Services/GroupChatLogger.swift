import Darwin
import Foundation

@MainActor
final class GroupChatLogger {
    private static let maxRetainedMessages = 2_000
    private static let maxChatLogSizeBytes = 2_000_000
    private static let maxRememberedLines = 4_000

    let directory: String
    let chatLogPath: String

    private var watchSource: (any DispatchSourceFileSystemObject)?
    private var lastFileOffset: UInt64 = 0
    private var onNewMessage: ((String, String) -> Void)?
    private var recentAppWrites: Set<String> = []
    private var seenLogLines: Set<String> = []
    private var seenLogLineOrder: [String] = []

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
        return chatStorageRoot() + "/chats/\(String(hashValue, radix: 16))"
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

        appendLineToChatLog(line)
    }

    func loadExistingMessages() -> [(sender: String, text: String)] {
        guard let data = try? String(contentsOfFile: chatLogPath, encoding: .utf8) else {
            return []
        }
        return data.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                rememberSeenLine(line)
                return parseLine(line)
            }
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
        if let attrs = try? FileManager.default.attributesOfItem(atPath: chatLogPath),
           let size = attrs[.size] as? UInt64,
           size < lastFileOffset {
            lastFileOffset = 0
        }

        guard let handle = FileHandle(forReadingAtPath: chatLogPath) else { return }
        handle.seek(toFileOffset: lastFileOffset)
        let data = handle.readDataToEndOfFile()
        try? handle.close()

        lastFileOffset += UInt64(data.count)

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            if recentAppWrites.remove(line) != nil {
                rememberSeenLine(line)
                continue
            }
            if seenLogLines.contains(line) { continue }
            rememberSeenLine(line)
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

    private func appendLineToChatLog(_ line: String) {
        let directoryURL = URL(fileURLWithPath: chatLogPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: chatLogPath) {
            FileManager.default.createFile(atPath: chatLogPath, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: chatLogPath) else { return }
        let fd = handle.fileDescriptor

        guard flock(fd, LOCK_EX) == 0 else {
            try? handle.close()
            return
        }

        defer {
            flock(fd, LOCK_UN)
            try? handle.close()
        }

        handle.seek(toFileOffset: 0)
        let existingData = handle.readDataToEndOfFile()
        let updatedData = compactedChatLogData(appending: line, existingData: existingData)

        try? handle.truncate(atOffset: 0)
        handle.seek(toFileOffset: 0)
        handle.write(updatedData)
        lastFileOffset = UInt64(updatedData.count)
    }

    private static func chatStorageRoot() -> String {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let rootURL = appSupport.appendingPathComponent("Trivium", isDirectory: true)
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            return rootURL.path
        }

        let fallback = NSHomeDirectory() + "/Library/Application Support/Trivium"
        try? FileManager.default.createDirectory(atPath: fallback, withIntermediateDirectories: true)
        return fallback
    }

    private func compactedChatLogData(appending line: String, existingData: Data) -> Data {
        var lines = String(data: existingData, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty } ?? []

        lines.append(line)
        if lines.count > Self.maxRetainedMessages {
            lines = Array(lines.suffix(Self.maxRetainedMessages))
        }

        var data = Data((lines.joined(separator: "\n") + "\n").utf8)
        while data.count > Self.maxChatLogSizeBytes, lines.count > 1 {
            let trimCount = min(max(lines.count / 10, 1), lines.count - 1)
            lines.removeFirst(trimCount)
            data = Data((lines.joined(separator: "\n") + "\n").utf8)
        }

        return data
    }

    private func rememberSeenLine(_ line: String) {
        guard !seenLogLines.contains(line) else { return }

        seenLogLines.insert(line)
        seenLogLineOrder.append(line)

        while seenLogLineOrder.count > Self.maxRememberedLines {
            let removed = seenLogLineOrder.removeFirst()
            seenLogLines.remove(removed)
        }
    }
}
