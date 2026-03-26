import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            // ZStack keeps ALL views alive -- terminals aren't destroyed when
            // you switch tabs. Only the selected view is visible/interactive.
            // Non-selected views are pushed offscreen to prevent NSView interference.
            ZStack {
                ChatRoomView()
                    .zIndex(appState.selectedSidebarItem == .chat ? 1 : 0)
                    .offset(x: appState.selectedSidebarItem == .chat ? 0 : -99999)

                ForEach(appState.agents) { agent in
                    let isSelected = appState.selectedSidebarItem == .agent(agent.id)
                    AgentSessionView(agent: agent, isActive: isSelected)
                        .id(agent.id)
                        .zIndex(isSelected ? 1 : 0)
                        .offset(x: isSelected ? 0 : -99999)
                }

                if appState.selectedSidebarItem == nil {
                    ContentUnavailableView("Select a Chat", systemImage: "bubble.left.and.bubble.right")
                        .zIndex(1)
                }
            }
        }
    }
}
