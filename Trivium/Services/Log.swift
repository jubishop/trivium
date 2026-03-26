import Foundation

enum Log {
    private static let logDir = "/tmp/trivium/logs"
    private static let logPath = "/tmp/trivium/logs/trivium.log"

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

        _ = ensureDir
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: logPath) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(entry.utf8))
        try? handle.close()
    }
}
