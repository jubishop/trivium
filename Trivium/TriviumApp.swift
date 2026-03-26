import SwiftUI

@main
struct TriviumApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    seedDefaultAgents()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 700)
    }

    private func seedDefaultAgents() {
        guard appState.agents.isEmpty else { return }
        _ = appState.addAgent(name: "Claude", type: .claude)
        _ = appState.addAgent(name: "Codex", type: .codex)
    }
}
