import AppKit
import Combine
import SwiftUI

// MARK: - InputBarState

@MainActor
final class InputBarState: ObservableObject {
    let editorSession = EditorSession()
    private(set) var editorView: EditorView?
    let keyHandler = InputBarKeyHandler()

    @Published private(set) var isEmpty: Bool = true
    @Published private(set) var displayLineCount: Int = 1

    private var sessionCancellable: AnyCancellable?

    func createView(theme: TerminalTheme, fontFamily: String, fontSize: Double) {
        guard editorView == nil else { return }
        editorSession.wordWrapEnabled = true
        editorSession.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize)
        if let view = editorSession.editorView as? EditorView {
            view.delegate = keyHandler
            editorView = view
        }

        // Track text changes to update isEmpty/displayLineCount for SwiftUI.
        // EditorSession publishes cursorPosition on every mutation, which is
        // the most reliable change signal without modifying EditorSession.
        sessionCancellable = editorSession.$cursorPosition
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncDerivedState()
            }
    }

    func clear() {
        editorSession.selectAll()
        editorSession.deleteBackward()
    }

    var isContentEmpty: Bool {
        editorSession.storage.lineCount == 1 && editorSession.storage.lineLength(0) == 0
    }

    private func syncDerivedState() {
        let newEmpty = isContentEmpty
        let newLineCount = editorSession.storage.lineCount
        if isEmpty != newEmpty { isEmpty = newEmpty }
        if displayLineCount != newLineCount { displayLineCount = newLineCount }
    }
}

// MARK: - InputBarKeyHandler

@MainActor
final class InputBarKeyHandler: EditorViewDelegate {
    weak var terminalSession: TerminalSession?
    var onDismiss: (() -> Void)?
    var onClear: (() -> Void)?

    func editorView(_ editorView: EditorView, handleKeyDown event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape key
        if let chars = event.charactersIgnoringModifiers, chars == "\u{1b}" {
            onDismiss?()
            return true
        }

        // Ctrl+key forwarding
        if mods.contains(.control), let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "c":
                terminalSession?.send(text: "\u{03}")
                return true
            case "d":
                terminalSession?.send(text: "\u{04}")
                return true
            case "z":
                terminalSession?.send(text: "\u{1a}")
                return true
            default:
                break
            }
        }

        return false
    }

    func editorView(_ editorView: EditorView, handleSpecialKey key: NSEvent.SpecialKey, mods: NSEvent.ModifierFlags) -> Bool {
        guard let session = editorView.session else { return false }
        let isSingleLine = session.storage.lineCount <= 1

        switch key {
        case .carriageReturn, .newline, .enter:
            if mods.contains(.shift) {
                return false // Pass through — insert newline in editor
            }
            guard let terminalSession else { return true }
            let text = session.storage.entireString()
            terminalSession.sendFromInputBar(text: text)
            onClear?()
            return true

        case .tab:
            terminalSession?.send(text: "\t")
            return true

        case .upArrow:
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                terminalSession?.send(text: "\u{1b}[A")
                return true
            }
            return false

        case .downArrow:
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                terminalSession?.send(text: "\u{1b}[B")
                return true
            }
            return false

        default:
            return false
        }
    }
}

// MARK: - InputBarView

struct InputBarView: View {
    @ObservedObject var inputBarState: InputBarState
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(0.15))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                Text(">")
                    .font(.custom(fontFamily, size: fontSize))
                    .foregroundStyle(theme.swiftUIColor(from: theme.green))
                    .padding(.top, 6)

                ZStack(alignment: .topLeading) {
                    if inputBarState.isEmpty {
                        Text("Type a command...")
                            .font(.custom(fontFamily, size: fontSize))
                            .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.3))
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }

                    if let editorView = inputBarState.editorView {
                        GeometryReader { geo in
                            EditorViewRepresentable(editorView: editorView)
                                .onAppear {
                                    editorView.setFrameSize(geo.size)
                                    editorView.sizeDidChange(geo.size)
                                }
                                .onChange(of: geo.size) { _, newSize in
                                    editorView.setFrameSize(newSize)
                                    editorView.sizeDidChange(newSize)
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: editorHeight)
            .background(theme.swiftUIColor(from: theme.background).opacity(0.95))
        }
    }

    private var editorHeight: CGFloat {
        let lineHeight = CGFloat(fontSize) * 1.5
        let lines = min(max(inputBarState.displayLineCount, 1), 4)
        return CGFloat(lines) * lineHeight + 12
    }
}
