import Foundation

let inputData = FileHandle.standardInput.readDataToEndOfFile()

func output(_ dict: [String: Any]) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: dict)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func allowDecision() -> [String: Any] {
    ["hookSpecificOutput": ["decision": ["behavior": "allow"]]]
}

func denyDecision(_ message: String) -> [String: Any] {
    ["hookSpecificOutput": ["decision": ["behavior": "deny", "message": message]]]
}

func fallthrough_() -> [String: Any] {
    ["hookSpecificOutput": ["decision": ["behavior": "ask"]]]
}

guard let permDir = ProcessInfo.processInfo.environment["TRIVIUM_PERMISSIONS_DIR"],
      !permDir.isEmpty else {
    output(fallthrough_())
}

guard let input = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
    output(fallthrough_())
}

let toolName = input["tool_name"] as? String ?? "unknown"

// Serialize tool_input back to a JSON string for display
let toolInputRaw = input["tool_input"] ?? [:]
let toolInputString: String
if let toolInputData = try? JSONSerialization.data(withJSONObject: toolInputRaw, options: [.sortedKeys]),
   let str = String(data: toolInputData, encoding: .utf8) {
    toolInputString = str
} else {
    toolInputString = "{}"
}

let requestID = UUID().uuidString

let request: [String: Any] = [
    "id": requestID,
    "tool_name": toolName,
    "tool_input": toolInputString,
    "timestamp": ISO8601DateFormatter().string(from: Date()),
]

try? FileManager.default.createDirectory(atPath: permDir, withIntermediateDirectories: true)
let requestPath = "\(permDir)/\(requestID).request.json"
let responsePath = "\(permDir)/\(requestID).response.json"

if let requestData = try? JSONSerialization.data(withJSONObject: request) {
    try? requestData.write(to: URL(fileURLWithPath: requestPath))
}

// Poll for response (5 minute timeout)
let deadline = Date().addingTimeInterval(300)

while Date() < deadline {
    if FileManager.default.fileExists(atPath: responsePath) {
        if let responseData = try? Data(contentsOf: URL(fileURLWithPath: responsePath)),
           let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let granted = response["granted"] as? Bool {
            try? FileManager.default.removeItem(atPath: requestPath)
            try? FileManager.default.removeItem(atPath: responsePath)
            if granted {
                output(allowDecision())
            } else {
                output(denyDecision("Permission denied by user"))
            }
        }
        break
    }
    Thread.sleep(forTimeInterval: 0.2)
}

// Timeout or unreadable response
try? FileManager.default.removeItem(atPath: requestPath)
try? FileManager.default.removeItem(atPath: responsePath)
output(denyDecision("Permission request timed out"))
