import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .disconnected: .gray
        case .idle: .green
        case .processing: .orange
        case .error: .red
        }
    }
}
