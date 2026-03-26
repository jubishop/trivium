import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            switch appState.selectedSidebarItem {
            case .chat:
                ChatRoomView()
            case .agent(let agentID):
                if let agent = appState.agent(withID: agentID) {
                    AgentSessionView(agent: agent)
                } else {
                    ContentUnavailableView("Agent Not Found", systemImage: "questionmark.circle")
                }
            case nil:
                ContentUnavailableView("Select a Chat", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }
}
