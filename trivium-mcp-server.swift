#!/usr/bin/env swift

// Trivium MCP Server (Global)
// A single MCP server that routes group chat messages by directory.
// Each tool call includes a `directory` param to scope the chat log.
// Chat logs are stored at /tmp/trivium/chats/<hash>/group-chat.jsonl

import Foundation

func chatLogPath(for directory: String) -> String {
    let normalized = (directory as NSString).standardizingPath
    let hashValue = normalized.utf8.reduce(into: UInt64(5381)) { hash, byte in
        hash = hash &* 33 &+ UInt64(byte)
    }
    let hash = String(hashValue, radix: 16)
    let dir = "/tmp/trivium/chats/\(hash)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/group-chat.jsonl"
}

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: Int?
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
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}

func respond(id: Int?, result: Any) {
    let response: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id as Any,
        "result": result,
    ]
    if let data = try? JSONSerialization.data(withJSONObject: response),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func handleInitialize(id: Int?) {
    respond(id: id, result: [
        "protocolVersion": "2024-11-05",
        "capabilities": ["tools": ["listChanged": false]],
        "serverInfo": ["name": "trivium-group-chat", "version": "2.0.0"],
    ] as [String: Any])
}

func handleToolsList(id: Int?) {
    respond(id: id, result: [
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

func handleToolCall(id: Int?, params: [String: Any]?) {
    guard let name = params?["name"] as? String else {
        respond(id: id, result: ["content": [["type": "text", "text": "Error: missing tool name"]]])
        return
    }
    let args = params?["arguments"] as? [String: Any] ?? [:]

    guard let directory = args["directory"] as? String else {
        respond(id: id, result: [
            "content": [["type": "text", "text": "Error: 'directory' argument is required"]],
        ])
        return
    }

    let logPath = chatLogPath(for: directory)

    switch name {
    case "get_group_chat":
        let lastN = (args["last_n"] as? Int) ?? 50
        let messages = readChatLog(path: logPath, lastN: lastN)
        let text = messages.isEmpty
            ? "No group chat messages yet for \(directory)."
            : messages.joined(separator: "\n")
        respond(id: id, result: ["content": [["type": "text", "text": text]]])

    case "send_to_group_chat":
        guard let message = args["message"] as? String else {
            respond(id: id, result: ["content": [["type": "text", "text": "Error: missing 'message'"]]])
            return
        }
        let senderName = (args["your_name"] as? String) ?? "agent"
        appendToChatLog(path: logPath, sender: senderName, text: message)
        respond(id: id, result: ["content": [["type": "text", "text": "Message posted to group chat."]]])

    default:
        respond(id: id, result: ["content": [["type": "text", "text": "Error: unknown tool '\(name)'"]]])
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

    let lineData = Data((line + "\n").utf8)
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    guard let handle = FileHandle(forWritingAtPath: path) else { return }
    handle.seekToEndOfFile()
    handle.write(lineData)
    try? handle.close()
}

// Main loop
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
        continue
    }

    switch request.method {
    case "initialize":
        handleInitialize(id: request.id)
    case "notifications/initialized":
        break
    case "tools/list":
        handleToolsList(id: request.id)
    case "tools/call":
        handleToolCall(id: request.id, params: request.params?.value as? [String: Any])
    default:
        if request.id != nil {
            respond(id: request.id, result: ["error": "Unknown method: \(request.method)"])
        }
    }
}
