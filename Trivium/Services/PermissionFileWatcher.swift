import Darwin
import Foundation

@MainActor
final class PermissionFileWatcher {
    let permissionsDir: String
    private var watchSource: (any DispatchSourceFileSystemObject)?
    private var knownRequests: Set<String> = []
    private var onNewRequest: ((String, String, String, String) -> Void)?

    init(directory: String) {
        let chatDir = GroupChatLogger.chatLogDir(for: directory)
        permissionsDir = chatDir + "/permissions"
        try? FileManager.default.createDirectory(atPath: permissionsDir, withIntermediateDirectories: true)
    }

    func startWatching(onNewRequest: @escaping (_ id: String, _ toolName: String, _ toolInput: String, _ timestamp: String) -> Void) {
        self.onNewRequest = onNewRequest

        guard let handle = FileHandle(forReadingAtPath: permissionsDir) else {
            // Try harder: ensure directory exists
            try? FileManager.default.createDirectory(atPath: permissionsDir, withIntermediateDirectories: true)
            guard let h = FileHandle(forReadingAtPath: permissionsDir) else { return }
            startSource(handle: h)
            return
        }
        startSource(handle: handle)
    }

    private func startSource(handle: FileHandle) {
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scanForRequests()
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

    func writeResponse(id: String, granted: Bool) {
        let response: [String: Any] = ["id": id, "granted": granted]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        let path = "\(permissionsDir)/\(id).response.json"
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func scanForRequests() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: permissionsDir) else { return }

        for file in files where file.hasSuffix(".request.json") {
            let id = String(file.dropLast(".request.json".count))
            guard !knownRequests.contains(id) else { continue }
            knownRequests.insert(id)

            let path = "\(permissionsDir)/\(file)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reqID = json["id"] as? String,
                  let toolName = json["tool_name"] as? String else { continue }

            let toolInput = json["tool_input"] as? String ?? "{}"
            let timestamp = json["timestamp"] as? String ?? ""

            onNewRequest?(reqID, toolName, toolInput, timestamp)
        }
    }
}
