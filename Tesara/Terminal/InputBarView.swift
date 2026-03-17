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
    let completionController = TabCompletionController()

    @Published private(set) var isEmpty: Bool = true
    @Published private(set) var displayLineCount: Int = 1
    @Published private(set) var displayPath: String?
    @Published private(set) var gitBranch: String?

    /// Ghost text suffix for autosuggestion (not @Published — drives Metal, not SwiftUI).
    fileprivate(set) var ghostSuffix: String?

    /// Visual hint appended to ghost text so users discover Right arrow accepts.
    static let ghostHintSuffix = " →"

    private var sessionCancellable: AnyCancellable?
    private var cwdCancellable: AnyCancellable?
    private var promptInfoGeneration: UInt64 = 0

    func createView(theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        guard editorView == nil else { return }
        editorSession.wordWrapEnabled = true
        editorSession.setSyntaxHighlighter(SyntaxHighlighter(tokenizer: ShellTokenizer()))
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

        // Live-filter completion popup if active
        if completionController.isActive {
            if cursorPosition.line != completionController.replacementLine {
                completionController.dismiss()
            } else {
                let lineText = editorSession.storage.lineContent(cursorPosition.line)
                completionController.updateFilter(lineText: lineText, cursorColumn: cursorPosition.column)
            }
        }

        // Update ghost suggestion
        updateGhostSuffix(cursorPosition: cursorPosition)
    }

    func observeSession() {
        guard let session = keyHandler.terminalSession else { return }
        updatePromptInfo(cwd: session.currentWorkingDirectory)
        cwdCancellable = session.$currentWorkingDirectory
            .removeDuplicates()
            .sink { [weak self] cwd in self?.updatePromptInfo(cwd: cwd) }
    }

    private static let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    private func updatePromptInfo(cwd: String?) {
        promptInfoGeneration &+= 1
        let gen = promptInfoGeneration
        guard let cwd, !cwd.isEmpty else {
            if displayPath != nil { displayPath = nil }
            if gitBranch != nil { gitBranch = nil }
            return
        }
        let home = Self.homePath
        let newPath = (cwd == home || cwd.hasPrefix(home + "/")) ? "~" + cwd.dropFirst(home.count) : cwd
        if displayPath != newPath { displayPath = newPath }
        Task.detached(priority: .utility) {
            let branch = GitBranchReader.branch(at: cwd)
            await MainActor.run { [weak self] in
                guard let self, self.promptInfoGeneration == gen else { return }
                if self.gitBranch != branch { self.gitBranch = branch }
            }
        }
    }

    /// Refresh ghost text (called after completion dismissal).
    func refreshGhostSuffix() {
        updateGhostSuffix(cursorPosition: editorSession.cursorPosition)
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

        // No ghost during history popup, search, or tab completion
        guard !historyController.isSearchActive && !historyController.isPopupActive && !completionController.isActive else {
            ghostSuffix = nil
            return
        }

        let text = storage.lineCount == 1 ? storage.lineContent(0) : storage.entireString()
        guard !text.isEmpty else {
            ghostSuffix = nil
            return
        }

        if let match = suggestionEngine.suggest(prefix: text) {
            ghostSuffix = String(match.dropFirst(text.count)) + Self.ghostHintSuffix
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

        // Escape — dismiss completion, dismiss popup, cancel search, dismiss ghost text, or clear input
        if let chars = event.charactersIgnoringModifiers, chars == "\u{1b}" {
            if let state = terminalSession?.inputBarState {
                if state.completionController.isActive {
                    state.completionController.dismiss()
                } else if state.historyController.isPopupActive {
                    state.historyController.dismissPopup(inputBarState: state)
                } else if state.historyController.isSearchActive {
                    state.historyController.cancelSearch()
                } else if state.ghostSuffix != nil {
                    state.ghostSuffix = nil
                    editorView.setNeedsRender()
                } else {
                    state.clear()
                }
            }
            return true
        }

        // Ctrl+key handling
        if mods.contains(.control), let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "c":
                terminalSession?.inputBarState?.completionController.dismiss()
                terminalSession?.inputBarState?.clear()
                terminalSession?.inputBarState?.historyController.reset()
                return true
            case "d":
                terminalSession?.send(text: "\u{04}")
                return true
            case "j":
                editorView.session?.insertNewline()
                return true
            case "p":
                let isSingleLine = (editorView.session?.storage.lineCount ?? 1) <= 1
                guard isSingleLine else { return true }
                historyPopupUp()
                return true
            case "n":
                let isSingleLine = (editorView.session?.storage.lineCount ?? 1) <= 1
                guard isSingleLine else { return true }
                historyPopupDown()
                return true
            case "r":
                terminalSession?.inputBarState?.completionController.dismiss()
                terminalSession?.inputBarState?.historyController.dismissPopupSilently()
                terminalSession?.inputBarState?.historyController.beginSearch()
                return true
            case "z":
                terminalSession?.send(text: "\u{1a}")
                return true
            default:
                break
            }
        }

        // Dismiss history popup on any unhandled character key; restore original
        // input, then let the character pass through to the editor.
        // Skip special keys (arrows, enter, tab, etc.) — they are handled in
        // handleSpecialKey with their own popup-aware logic.
        if event.specialKey == nil,
           let state = terminalSession?.inputBarState, state.historyController.isPopupActive {
            state.historyController.dismissPopup(inputBarState: state)
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
            if let state = terminalSession?.inputBarState, state.completionController.isActive {
                state.completionController.acceptSelected()
                return true
            }
            if let state = terminalSession?.inputBarState, state.historyController.isPopupActive {
                state.historyController.acceptPopupSelection()
                // Fall through — input bar already has the selected command
            }
            guard let terminalSession else { return true }
            let text = session.storage.entireString()
            terminalSession.sendFromInputBar(text: text)
            terminalSession.inputBarState?.clear()
            terminalSession.inputBarState?.historyController.reset()
            return true

        case .tab:
            guard let state = terminalSession?.inputBarState else {
                terminalSession?.send(text: "\t")
                return true
            }
            if state.completionController.isActive {
                state.completionController.acceptSelected()
            } else {
                state.historyController.dismissPopupSilently()
                let pos = session.cursorPosition
                let lineText = session.storage.lineContent(pos.line)
                state.completionController.triggerCompletion(
                    lineText: lineText,
                    line: pos.line,
                    cursorColumn: pos.column,
                    cwd: terminalSession?.currentWorkingDirectory
                )
            }
            return true

        case .upArrow:
            if let state = terminalSession?.inputBarState, state.completionController.isActive {
                state.completionController.selectPrevious()
                return true
            }
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                historyPopupUp()
                return true
            }
            return false

        case .downArrow:
            if let state = terminalSession?.inputBarState, state.completionController.isActive {
                state.completionController.selectNext()
                return true
            }
            if isSingleLine && !mods.contains(.command) && !mods.contains(.option) {
                historyPopupDown()
                return true
            }
            return false

        case .rightArrow:
            if let state = terminalSession?.inputBarState,
               let ghostSuffix = state.ghostSuffix,
               !ghostSuffix.isEmpty,
               session.isCursorAtDocumentEnd {
                let suggestion = String(ghostSuffix.dropLast(InputBarState.ghostHintSuffix.count))
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

    private func historyPopupUp() {
        guard let state = terminalSession?.inputBarState else { return }
        if state.historyController.isPopupActive {
            state.historyController.popupSelectPrevious(inputBarState: state)
        } else {
            state.completionController.dismiss()
            state.historyController.openPopup(currentText: state.currentText(), inputBarState: state)
        }
    }

    private func historyPopupDown() {
        guard let state = terminalSession?.inputBarState else { return }
        if state.historyController.isPopupActive {
            state.historyController.popupSelectNext(inputBarState: state)
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
    let showPromptInfo: Bool
    var maxHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(theme.dividerOpacity))
                .frame(height: 1)

            if showPromptInfo, let displayPath = inputBarState.displayPath {
                promptInfoRow(path: displayPath, branch: inputBarState.gitBranch)
            }

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

    /// Fixed vertical overhead: divider (1) + top padding (8) + bottom padding (10).
    private static let fixedOverhead: CGFloat = 19

    private var maxLines: Int {
        guard maxHeight > 0 else { return 4 }
        let overhead = Self.fixedOverhead + promptInfoHeight
        let available = maxHeight - overhead
        return max(1, Int(available / editorLineHeight))
    }

    private var textAreaHeight: CGFloat {
        let lines = min(max(inputBarState.displayLineCount, 1), maxLines)
        return CGFloat(lines) * editorLineHeight
    }

    private static let promptInfoFontScale: CGFloat = 0.85

    private var promptInfoHeight: CGFloat {
        showPromptInfo && inputBarState.displayPath != nil ? ceil(fontSize * Self.promptInfoFontScale * 1.2) + 8 : 0
    }

    private var totalHeight: CGFloat {
        textAreaHeight + Self.fixedOverhead + promptInfoHeight
    }

    private func promptInfoRow(path: String, branch: String?) -> some View {
        HStack(spacing: 4) {
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
            if let branch {
                Text("·")
                Image(systemName: "arrow.triangle.branch")
                Text(branch)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.custom(fontFamily, size: fontSize * Self.promptInfoFontScale))
        .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.35))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
