#!/usr/bin/env swift

// Trivium MCP Server
// A lightweight MCP server that exposes group chat history to CLI agents.
// Speaks JSON-RPC 2.0 over stdio per the MCP protocol.

import Foundation

let chatLogPath: String = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments[1]
    }
    return NSTemporaryDirectory() + "trivium-group-chat.jsonl"
}()

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
        "capabilities": [
            "tools": [
                "listChanged": false,
            ],
        ],
        "serverInfo": [
            "name": "trivium-group-chat",
            "version": "1.0.0",
        ],
    ] as [String: Any])
}

func handleToolsList(id: Int?) {
    respond(id: id, result: [
        "tools": [
            [
                "name": "get_group_chat",
                "description": "Get recent messages from the Trivium group chat. Use this to see what has been discussed in the group chat room with other agents and the user.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "last_n": [
                            "type": "number",
                            "description": "Number of recent messages to retrieve (default: 50)",
                        ],
                    ],
                    "required": [] as [String],
                ],
            ],
            [
                "name": "send_to_group_chat",
                "description": "Post a message to the Trivium group chat that all agents and the user can see.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "message": [
                            "type": "string",
                            "description": "The message to post to the group chat",
                        ],
                    ],
                    "required": ["message"],
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

    switch name {
    case "get_group_chat":
        let lastN = (args["last_n"] as? Int) ?? 50
        let messages = readChatLog(lastN: lastN)
        let text = messages.isEmpty
            ? "No group chat messages yet."
            : messages.joined(separator: "\n")
        respond(id: id, result: [
            "content": [["type": "text", "text": text]],
        ])

    case "send_to_group_chat":
        if let message = args["message"] as? String {
            appendToChatLog(sender: "agent", text: message)
            respond(id: id, result: [
                "content": [["type": "text", "text": "Message posted to group chat."]],
            ])
        } else {
            respond(id: id, result: [
                "content": [["type": "text", "text": "Error: missing 'message' argument"]],
            ])
        }

    default:
        respond(id: id, result: [
            "content": [["type": "text", "text": "Error: unknown tool '\(name)'"]],
        ])
    }
}

func readChatLog(lastN: Int) -> [String] {
    guard let data = try? String(contentsOfFile: chatLogPath, encoding: .utf8) else {
        return []
    }
    let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
    let recent = Array(lines.suffix(lastN))

    return recent.compactMap { line in
        guard let jsonData = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let sender = entry["sender"] as? String,
              let text = entry["text"] as? String,
              let timestamp = entry["timestamp"] as? String else {
            return nil
        }
        return "[\(timestamp)] \(sender): \(text)"
    }
}

func appendToChatLog(sender: String, text: String) {
    let entry: [String: Any] = [
        "sender": sender,
        "text": text,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: entry),
          let line = String(data: data, encoding: .utf8) else { return }

    let lineData = (line + "\n").data(using: .utf8)!

    // O_APPEND ensures atomic positioning at EOF per write call.
    // Each JSONL line is well under PIPE_BUF (4096), so writes won't interleave.
    let fd = open(chatLogPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    guard fd >= 0 else { return }
    lineData.withUnsafeBytes { buf in
        _ = write(fd, buf.baseAddress!, buf.count)
    }
    close(fd)
}

// Main loop: read JSON-RPC from stdin line by line
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
        // Client ack, no response needed
        break

    case "tools/list":
        handleToolsList(id: request.id)

    case "tools/call":
        let params = request.params?.value as? [String: Any]
        handleToolCall(id: request.id, params: params)

    default:
        if request.id != nil {
            respond(id: request.id, result: ["error": "Unknown method: \(request.method)"])
        }
    }
}
