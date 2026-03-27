import SwiftUI

struct PermissionRequestView: View {
    @Environment(AppState.self) private var appState
    let request: PermissionRequest
    let agentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                Text("Wants to use: **\(request.toolName)**")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(formattedInput)
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                Spacer()

                Button {
                    appState.denyPermission(request.id)
                } label: {
                    Text("Deny")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    appState.approvePermission(request.id)
                } label: {
                    Text("Allow")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(10)
        .background(agentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(agentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var formattedInput: String {
        // Try to pretty-print JSON, otherwise show raw
        if let data = request.toolInput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return request.toolInput
    }
}
