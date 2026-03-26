import SwiftUI
import SwiftTerm

struct TerminalViewRepresentable: NSViewRepresentable {
    let executable: String
    let args: [String]
    let environment: [String]?
    let workingDirectory: String?
    var isActive: Bool = true
    let onProcessTerminated: ((Int32) -> Void)?

    func makeNSView(context: Context) -> FocusableTerminalView {
        let wrapper = FocusableTerminalView()
        let terminalView = wrapper.terminalView
        terminalView.processDelegate = context.coordinator

        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminalView.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        terminalView.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: nil,
            currentDirectory: workingDirectory
        )

        return wrapper
    }

    func updateNSView(_ nsView: FocusableTerminalView, context: Context) {
        // Grab focus when this terminal becomes active
        if isActive {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView.terminalView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcessTerminated: onProcessTerminated)
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onProcessTerminated: ((Int32) -> Void)?

        init(onProcessTerminated: ((Int32) -> Void)?) {
            self.onProcessTerminated = onProcessTerminated
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onProcessTerminated?(exitCode ?? -1)
        }
    }
}

// Wrapper NSView that ensures the terminal gets first responder status
// and intercepts arrow keys before SwiftUI's NavigationSplitView can grab them.
class FocusableTerminalView: NSView {
    let terminalView = LocalProcessTerminalView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Make the terminal first responder once it's in a window
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.terminalView)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the terminal handle all key events, preventing SwiftUI from
        // intercepting arrow keys for navigation
        if window?.firstResponder === terminalView || terminalView.isDescendant(of: self) {
            return terminalView.performKeyEquivalent(with: event)
        }
        return super.performKeyEquivalent(with: event)
    }
}
