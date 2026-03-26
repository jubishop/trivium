import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ChatRoomView()
            .frame(minWidth: 600, minHeight: 400)
    }
}
