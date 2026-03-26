import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddAgent = false

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedSidebarItem) {
            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .tag(SidebarItem.chat)
            }

            Section("Agents") {
                ForEach(appState.agents) { agent in
                    HStack(spacing: 8) {
                        Image(systemName: agent.icon)
                            .foregroundStyle(agent.color)
                            .frame(width: 20)

                        Text(agent.name)

                        Spacer()

                        StatusIndicator(status: agent.status)
                    }
                    .tag(SidebarItem.agent(agent.id))
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            appState.removeAgent(agent)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingAddAgent = true
            } label: {
                Label("Add Agent", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingAddAgent) {
            AddAgentSheet()
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
    }
}
