#!/usr/bin/env swift

// Trivium MCP Server (Global)
// A single MCP server that routes group chat messages by directory.
// Each tool call includes a `directory` param to scope the chat log.
// Chat logs are stored under ~/Library/Application Support/Trivium/chats/<hash>/group-chat.jsonl

import Darwin
import Foundation

let maxRetainedMessages = 2_000
let maxChatLogSizeBytes = 2_000_000

func chatStorageRoot() -> String {
    if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let root = appSupport.appendingPathComponent("Trivium", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    let fallback = NSHomeDirectory() + "/Library/Application Support/Trivium"
    try? FileManager.default.createDirectory(atPath: fallback, withIntermediateDirectories: true)
    return fallback
}

func chatLogPath(for directory: String) -> String {
    let normalized = (directory as NSString).standardizingPath
    let hashValue = normalized.utf8.reduce(into: UInt64(5381)) { hash, byte in
        hash = hash &* 33 &+ UInt64(byte)
    }
    let hash = String(hashValue, radix: 16)
    let dir = chatStorageRoot() + "/chats/\(hash)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/group-chat.jsonl"
}

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: AnyCodable?
    let method: String
    let params: AnyCodable?
}

struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}

final class StdioTransport {
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private var buffer = Data()
    private let headerDelimiter = Data("\r\n\r\n".utf8)

    func readMessage() -> Data? {
        while true {
            if let headerRange = buffer.range(of: headerDelimiter),
               let contentLength = parseContentLength(from: buffer[..<headerRange.lowerBound]) {
                let bodyStart = headerRange.upperBound
                let availableBodyBytes = buffer.count - bodyStart

                if availableBodyBytes >= contentLength {
                    let bodyRange = bodyStart..<(bodyStart + contentLength)
                    let body = buffer.subdata(in: bodyRange)
                    buffer.removeSubrange(..<bodyRange.upperBound)
                    return body
                }
            }

            guard let chunk = try? input.read(upToCount: 4096),
                  !chunk.isEmpty else {
                return nil
            }

            buffer.append(chunk)
        }
    }

    func writeMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        output.write(Data(header.utf8))
        output.write(data)
    }

    private func parseContentLength(from headerData: Data.SubSequence) -> Int? {
        guard let headerText = String(data: Data(headerData), encoding: .utf8) else { return nil }

        for line in headerText.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return nil
    }
}

func respond(transport: StdioTransport, id: Any?, result: Any) {
    transport.writeMessage([
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "result": result,
    ])
}

func handleInitialize(transport: StdioTransport, id: Any?) {
    respond(transport: transport, id: id, result: [
        "protocolVersion": "2024-11-05",
        "capabilities": ["tools": ["listChanged": false]],
        "serverInfo": ["name": "trivium-group-chat", "version": "2.0.0"],
    ] as [String: Any])
}

func handleToolsList(transport: StdioTransport, id: Any?) {
    respond(transport: transport, id: id, result: [
        "tools": [
            [
                "name": "get_group_chat",
                "description": "Get recent messages from the Trivium group chat for the current project directory. Use this to see what has been discussed with other agents and the user.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "directory": [
                            "type": "string",
                            "description": "The project directory path (use your current working directory)",
                        ],
                        "last_n": [
                            "type": "number",
                            "description": "Number of recent messages to retrieve (default: 50)",
                        ],
                    ],
                    "required": ["directory"],
                ],
            ],
            [
                "name": "send_to_group_chat",
                "description": "Post a message to the Trivium group chat for the current project directory. All agents and the user can see it. You MUST include your_name.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "directory": [
                            "type": "string",
                            "description": "The project directory path (use your current working directory)",
                        ],
                        "message": [
                            "type": "string",
                            "description": "The message to post",
                        ],
                        "your_name": [
                            "type": "string",
                            "description": "Your name (e.g. 'Claude' or 'Codex')",
                        ],
                    ],
                    "required": ["directory", "message", "your_name"],
                ],
            ],
        ] as [[String: Any]],
    ])
}

func handleToolCall(transport: StdioTransport, id: Any?, params: [String: Any]?) {
    guard let name = params?["name"] as? String else {
        respond(transport: transport, id: id, result: ["content": [["type": "text", "text": "Error: missing tool name"]]])
        return
    }

    let args = params?["arguments"] as? [String: Any] ?? [:]

    guard let directory = args["directory"] as? String else {
        respond(transport: transport, id: id, result: [
            "content": [["type": "text", "text": "Error: 'directory' argument is required"]],
        ])
        return
    }

    let logPath = chatLogPath(for: directory)

    switch name {
    case "get_group_chat":
        let lastN = (args["last_n"] as? Int)
            ?? (args["last_n"] as? Double).map(Int.init)
            ?? 50
        let messages = readChatLog(path: logPath, lastN: lastN)
        let text = messages.isEmpty
            ? "No group chat messages yet for \(directory)."
            : messages.joined(separator: "\n")
        respond(transport: transport, id: id, result: ["content": [["type": "text", "text": text]]])

    case "send_to_group_chat":
        guard let message = args["message"] as? String else {
            respond(transport: transport, id: id, result: ["content": [["type": "text", "text": "Error: missing 'message'"]]])
            return
        }

        let senderName = (args["your_name"] as? String) ?? "agent"
        appendToChatLog(path: logPath, sender: senderName, text: message)
        respond(transport: transport, id: id, result: ["content": [["type": "text", "text": "Message posted to group chat."]]])

    default:
        respond(transport: transport, id: id, result: ["content": [["type": "text", "text": "Error: unknown tool '\(name)'"]]])
    }
}

func readChatLog(path: String, lastN: Int) -> [String] {
    guard let data = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return data.components(separatedBy: .newlines)
        .filter { !$0.isEmpty }
        .suffix(lastN)
        .compactMap { line in
            guard let jsonData = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let sender = entry["sender"] as? String,
                  let text = entry["text"] as? String,
                  let timestamp = entry["timestamp"] as? String else { return nil }
            return "[\(timestamp)] \(sender): \(text)"
        }
}

func appendToChatLog(path: String, sender: String, text: String) {
    let entry: [String: Any] = [
        "sender": sender,
        "text": text,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: entry),
          let line = String(data: data, encoding: .utf8) else { return }

    let directory = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }

    guard let handle = FileHandle(forWritingAtPath: path) else { return }
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
}

func compactedChatLogData(appending line: String, existingData: Data) -> Data {
    var lines = String(data: existingData, encoding: .utf8)?
        .components(separatedBy: .newlines)
        .filter { !$0.isEmpty } ?? []

    lines.append(line)
    if lines.count > maxRetainedMessages {
        lines = Array(lines.suffix(maxRetainedMessages))
    }

    var data = Data((lines.joined(separator: "\n") + "\n").utf8)
    while data.count > maxChatLogSizeBytes, lines.count > 1 {
        let trimCount = min(max(lines.count / 10, 1), lines.count - 1)
        lines.removeFirst(trimCount)
        data = Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    return data
}

let transport = StdioTransport()

while let data = transport.readMessage() {
    guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
        continue
    }

    let requestID = request.id?.value

    switch request.method {
    case "initialize":
        handleInitialize(transport: transport, id: requestID)
    case "notifications/initialized":
        break
    case "tools/list":
        handleToolsList(transport: transport, id: requestID)
    case "tools/call":
        handleToolCall(transport: transport, id: requestID, params: request.params?.value as? [String: Any])
    default:
        if requestID != nil {
            respond(transport: transport, id: requestID, result: ["error": "Unknown method: \(request.method)"])
        }
    }
}
