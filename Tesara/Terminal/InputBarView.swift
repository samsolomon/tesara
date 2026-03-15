import AppKit
import Combine
import SwiftUI

// MARK: - InputBarState

@MainActor
final class InputBarState: ObservableObject {
    let editorSession = EditorSession()
    @Published private(set) var editorView: EditorView?
    let keyHandler = InputBarKeyHandler()
    let historyController = InputBarHistoryController()
    let suggestionEngine = SuggestionEngine()

    @Published private(set) var isEmpty: Bool = true
    @Published private(set) var displayLineCount: Int = 1

    /// Ghost text suffix for autosuggestion (not @Published — drives Metal, not SwiftUI).
    fileprivate(set) var ghostSuffix: String?

    private var sessionCancellable: AnyCancellable?

    func createView(theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        guard editorView == nil else { return }
        editorSession.wordWrapEnabled = true
        editorSession.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorConfig, cursorBlink: cursorBlink)
        if let view = editorSession.editorView as? EditorView {
            view.delegate = keyHandler
            view.scrollbarDisabled = true
            view.ghostSuffixProvider = { [weak self] in self?.ghostSuffix }
            editorView = view
        }

        sessionCancellable = editorSession.$cursorPosition
            .removeDuplicates()
            .sink { [weak self] newPosition in
                self?.syncDerivedState(cursorPosition: newPosition)
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

    private func syncDerivedState(cursorPosition: TextStorage.Position) {
        let lineCount = editorSession.storage.lineCount
        let newEmpty = lineCount == 1 && editorSession.storage.lineLength(0) == 0
        if isEmpty != newEmpty { isEmpty = newEmpty }
        if displayLineCount != lineCount { displayLineCount = lineCount }

        // Update ghost suggestion
        updateGhostSuffix(cursorPosition: cursorPosition)
    }

    private func updateGhostSuffix(cursorPosition: TextStorage.Position) {
        // Only show ghost when cursor is at document end.
        // Use the passed-in position because @Published fires on willSet,
        // before the property is stored.
        let storage = editorSession.storage
        let lastLine = storage.lineCount - 1
        let lastCol = storage.lineLength(lastLine)
        guard cursorPosition.line == lastLine && cursorPosition.column == lastCol else {
            ghostSuffix = nil
            return
        }

        // No ghost during history navigation or search
        guard !historyController.isSearchActive && !historyController.isNavigatingHistory else {
            ghostSuffix = nil
            return
        }

        let text = storage.lineCount == 1 ? storage.lineContent(0) : storage.entireString()
        guard !text.isEmpty else {
            ghostSuffix = nil
            return
        }

        if let match = suggestionEngine.suggest(prefix: text) {
            ghostSuffix = String(match.dropFirst(text.count)) + " →"
        } else {
            ghostSuffix = nil
        }
    }
}

// MARK: - InputBarKeyHandler

@MainActor
final class InputBarKeyHandler: EditorViewDelegate {
    weak var terminalSession: TerminalSession?

    func editorView(_ editorView: EditorView, handleKeyDown event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape — cancel search, dismiss ghost text, or clear input
        if let chars = event.charactersIgnoringModifiers, chars == "\u{1b}" {
            if let state = terminalSession?.inputBarState,
               state.historyController.isSearchActive {
                state.historyController.cancelSearch()
            } else if let state = terminalSession?.inputBarState,
                      state.ghostSuffix != nil {
                state.ghostSuffix = nil
                editorView.setNeedsRender()
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

        case .rightArrow:
            if let state = terminalSession?.inputBarState,
               let ghostSuffix = state.ghostSuffix,
               !ghostSuffix.isEmpty,
               session.isCursorAtDocumentEnd {
                let suggestion = String(ghostSuffix.dropLast(2)) // strip " →"
                guard !suggestion.isEmpty else { return false }
                if mods.contains(.option) {
                    session.insertText(firstWord(of: suggestion))
                } else if mods.isDisjoint(with: [.shift, .control, .option, .command]) {
                    session.insertText(suggestion)
                } else {
                    return false
                }
                return true
            }
            return false

        default:
            return false
        }
    }

    private func firstWord(of text: String) -> String {
        var index = text.startIndex
        // Advance past word characters
        while index < text.endIndex && !text[index].isWhitespace {
            index = text.index(after: index)
        }
        // Include trailing whitespace
        while index < text.endIndex && text[index].isWhitespace {
            index = text.index(after: index)
        }
        return index > text.startIndex ? String(text[text.startIndex..<index]) : text
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
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(theme.dividerOpacity))
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
