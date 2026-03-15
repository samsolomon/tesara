import AppKit
import Combine
import SwiftUI

// MARK: - InputBarState

@MainActor
final class InputBarState: ObservableObject {
    let editorSession = EditorSession()
    private(set) var editorView: EditorView?
    let keyHandler = InputBarKeyHandler()
    let historyController = InputBarHistoryController()

    @Published private(set) var isEmpty: Bool = true
    @Published private(set) var displayLineCount: Int = 1
    @Published private(set) var isSearchActive: Bool = false

    private var sessionCancellable: AnyCancellable?
    private var searchCancellable: AnyCancellable?

    func createView(theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        guard editorView == nil else { return }
        editorSession.wordWrapEnabled = true
        editorSession.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorConfig, cursorBlink: cursorBlink)
        if let view = editorSession.editorView as? EditorView {
            view.delegate = keyHandler
            view.scrollbarDisabled = true
            editorView = view
        }

        sessionCancellable = editorSession.$cursorPosition
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncDerivedState()
            }

        searchCancellable = historyController.$isSearchActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                print("[Tesara-DEBUG] isSearchActive pipe: \(active), current=\(self?.isSearchActive ?? false)")
                if self?.isSearchActive != active {
                    self?.isSearchActive = active
                }
            }
    }

    func clear() {
        editorSession.selectAll()
        editorSession.deleteBackward()
    }

    func setText(_ text: String) {
        editorSession.selectAll()
        editorSession.deleteBackward()
        if !text.isEmpty {
            editorSession.insertText(text)
        }
    }

    func currentText() -> String {
        editorSession.storage.entireString()
    }

    private func syncDerivedState() {
        let lineCount = editorSession.storage.lineCount
        let newEmpty = lineCount == 1 && editorSession.storage.lineLength(0) == 0
        if isEmpty != newEmpty { isEmpty = newEmpty }
        if displayLineCount != lineCount { displayLineCount = lineCount }
    }
}

// MARK: - InputBarKeyHandler

@MainActor
final class InputBarKeyHandler: EditorViewDelegate {
    weak var terminalSession: TerminalSession?

    func editorView(_ editorView: EditorView, handleKeyDown event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape — cancel search if active, otherwise clear text
        if let chars = event.charactersIgnoringModifiers, chars == "\u{1b}" {
            if let state = terminalSession?.inputBarState,
               state.historyController.isSearchActive {
                state.historyController.cancelSearch()
            } else {
                terminalSession?.inputBarState?.clear()
            }
            return true
        }

        // Ctrl+key handling
        if mods.contains(.control), let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "c":
                terminalSession?.inputBarState?.clear()
                terminalSession?.inputBarState?.historyController.reset()
                return true
            case "d":
                terminalSession?.send(text: "\u{04}")
                return true
            case "j":
                editorView.session?.insertNewline()
                return true
            case "r":
                print("[Tesara-DEBUG] Ctrl+R pressed, beginSearch()")
                terminalSession?.inputBarState?.historyController.beginSearch()
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
            if mods.intersection([.shift, .control, .option]).isEmpty == false {
                return false
            }
            guard let terminalSession else { return true }
            let text = session.storage.entireString()
            terminalSession.sendFromInputBar(text: text)
            terminalSession.inputBarState?.clear()
            terminalSession.inputBarState?.historyController.reset()
            return true

        case .tab:
            terminalSession?.send(text: "\t")
            return true

        case .upArrow:
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                if let state = terminalSession?.inputBarState {
                    state.historyController.navigateUp(
                        currentText: state.currentText(),
                        inputBarState: state
                    )
                }
                return true
            }
            return false

        case .downArrow:
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                if let state = terminalSession?.inputBarState {
                    state.historyController.navigateDown(
                        currentText: state.currentText(),
                        inputBarState: state
                    )
                }
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

    private var dividerOpacity: Double {
        theme.isDarkBackground ? 0.22 : 0.14
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(dividerOpacity))
                .frame(height: 1)

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
            .frame(maxWidth: .infinity, minHeight: textAreaHeight, maxHeight: textAreaHeight, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(height: totalHeight, alignment: .top)
        .background(theme.swiftUIColor(from: theme.background))
    }

    private var editorLineHeight: CGFloat {
        max(inputBarState.editorView?.lineHeight ?? CGFloat(0), CGFloat(fontSize) * 1.5)
    }

    private var textAreaHeight: CGFloat {
        let lines = min(max(inputBarState.displayLineCount, 1), 4)
        return CGFloat(lines) * editorLineHeight
    }

    private var totalHeight: CGFloat {
        textAreaHeight + 19
    }
}
