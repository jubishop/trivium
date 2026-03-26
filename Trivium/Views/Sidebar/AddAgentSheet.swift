import SwiftUI

struct AddAgentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AgentType = .claude

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Agent")
                .font(.headline)

            Form {
                TextField("Name", text: $name)

                Picker("Type", selection: $type) {
                    ForEach(AgentType.allCases) { agentType in
                        HStack {
                            Image(systemName: agentType.icon)
                            Text(agentType.displayName)
                        }
                        .tag(agentType)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let finalName = name.isEmpty ? type.displayName : name
                    _ = appState.addAgent(name: finalName, type: type)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            name = nextDefaultName(for: type)
        }
        .onChange(of: type) { _, newType in
            name = nextDefaultName(for: newType)
        }
    }

    private func nextDefaultName(for type: AgentType) -> String {
        let base = type.displayName
        let existingNames = Set(appState.agents.map(\.name))
        if !existingNames.contains(base) { return base }
        var i = 2
        while existingNames.contains("\(base)-\(i)") { i += 1 }
        return "\(base)-\(i)"
    }
}
