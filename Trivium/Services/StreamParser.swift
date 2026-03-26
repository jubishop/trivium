import Foundation

struct StreamParser: Sendable {
    static func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let state = LineBuffer()

            handle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF: flush any remaining partial line
                    let remaining = state.flush()
                    if let remaining, !remaining.isEmpty {
                        continuation.yield(remaining)
                    }
                    continuation.finish()
                    return
                }

                let newLines = state.append(data)
                for line in newLines {
                    continuation.yield(line)
                }
            }

            continuation.onTermination = { @Sendable _ in
                handle.readabilityHandler = nil
            }
        }
    }
}

private final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let newline = UInt8(ascii: "\n")

    func append(_ data: Data) -> [String] {
        buffer.append(data)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])
        }
        return lines
    }

    func flush() -> String? {
        guard !buffer.isEmpty else { return nil }
        let result = String(data: buffer, encoding: .utf8)
        buffer = Data()
        return result
    }
}
