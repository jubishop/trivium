import Foundation

enum Log {
    private static let logDir = NSHomeDirectory() + "/Library/Logs/Trivium"
    private static let logPath = NSHomeDirectory() + "/Library/Logs/Trivium/trivium.log"
    private static let archivedLogPath = logPath + ".1"
    private static let maxLogSizeBytes = 1_000_000
    private static let lock = NSLock()

    private static let ensureDir: Void = {
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    }()

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        write("INFO", message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        write("ERROR", message, file: file, line: line)
    }

    private static func write(_ level: String, _ message: String, file: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] [\(level)] \(fileName):\(line) \(message)\n"

        lock.lock()
        defer { lock.unlock() }

        _ = ensureDir
        rotateIfNeeded()

        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(entry.utf8))
        try? handle.close()
    }

    private static func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64,
              size >= maxLogSizeBytes else { return }

        if FileManager.default.fileExists(atPath: archivedLogPath) {
            try? FileManager.default.removeItem(atPath: archivedLogPath)
        }

        try? FileManager.default.moveItem(atPath: logPath, toPath: archivedLogPath)
    }
}
