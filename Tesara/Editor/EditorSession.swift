import AppKit

@MainActor
final class EditorSession: ObservableObject, Identifiable {

    let id = UUID()

    // MARK: - State

    let storage = TextStorage()
    let undoManager: UndoManager = {
        let um = UndoManager()
        um.groupsByEvent = false
        return um
    }()

    @Published var cursorPosition = TextStorage.Position(line: 0, column: 0)
    @Published var selection: TextStorage.Range?

    /// Set by EditorView in 5C. Nil until `createView()` is called.
    @Published private(set) var editorView: NSView?

    /// Called after any mutation to signal the view needs redraw. Set by EditorView.
    var needsRenderCallback: (() -> Void)?

    // MARK: - Cursor Movement

    enum CursorDirection {
        case left, right, up, down
        case wordLeft, wordRight
        case lineStart, lineEnd
        case documentStart, documentEnd
    }

    func moveCursor(_ direction: CursorDirection, extending: Bool = false) {
        let oldPos = cursorPosition
        let newPos: TextStorage.Position

        switch direction {
        case .left:
            if let sel = selection, !extending {
                newPos = sel.normalized.start
            } else if cursorPosition.column > 0 {
                newPos = TextStorage.Position(line: cursorPosition.line, column: cursorPosition.column - 1)
            } else if cursorPosition.line > 0 {
                let prevLine = cursorPosition.line - 1
                newPos = TextStorage.Position(line: prevLine, column: storage.lineLength(prevLine))
            } else {
                newPos = cursorPosition
            }

        case .right:
            if let sel = selection, !extending {
                newPos = sel.normalized.end
            } else if cursorPosition.column < storage.lineLength(cursorPosition.line) {
                newPos = TextStorage.Position(line: cursorPosition.line, column: cursorPosition.column + 1)
            } else if cursorPosition.line < storage.lineCount - 1 {
                newPos = TextStorage.Position(line: cursorPosition.line + 1, column: 0)
            } else {
                newPos = cursorPosition
            }

        case .up:
            if cursorPosition.line > 0 {
                let targetLine = cursorPosition.line - 1
                let col = min(cursorPosition.column, storage.lineLength(targetLine))
                newPos = TextStorage.Position(line: targetLine, column: col)
            } else {
                newPos = TextStorage.Position(line: 0, column: 0)
            }

        case .down:
            if cursorPosition.line < storage.lineCount - 1 {
                let targetLine = cursorPosition.line + 1
                let col = min(cursorPosition.column, storage.lineLength(targetLine))
                newPos = TextStorage.Position(line: targetLine, column: col)
            } else {
                let lastLine = storage.lineCount - 1
                newPos = TextStorage.Position(line: lastLine, column: storage.lineLength(lastLine))
            }

        case .wordLeft:
            newPos = storage.wordBoundary(from: cursorPosition, direction: .left)

        case .wordRight:
            newPos = storage.wordBoundary(from: cursorPosition, direction: .right)

        case .lineStart:
            newPos = TextStorage.Position(line: cursorPosition.line, column: 0)

        case .lineEnd:
            newPos = TextStorage.Position(line: cursorPosition.line, column: storage.lineLength(cursorPosition.line))

        case .documentStart:
            newPos = TextStorage.Position(line: 0, column: 0)

        case .documentEnd:
            let lastLine = storage.lineCount - 1
            newPos = TextStorage.Position(line: lastLine, column: storage.lineLength(lastLine))
        }

        cursorPosition = newPos

        if extending {
            let anchor = selection?.start ?? oldPos
            if anchor == newPos {
                selection = nil
            } else {
                selection = TextStorage.Range(start: anchor, end: newPos)
            }
        } else {
            selection = nil
        }
    }

    // MARK: - Text Input

    private func withUndoGroup(_ body: () -> Void) {
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    func insertText(_ text: String) {
        withUndoGroup {
            if let sel = selection {
                cursorPosition = storage.replace(range: sel.normalized, with: text, undoManager: undoManager)
                selection = nil
            } else {
                cursorPosition = storage.insert(text, at: cursorPosition, undoManager: undoManager)
            }
        }
        needsRenderCallback?()
    }

    func deleteBackward() {
        withUndoGroup {
            if let sel = selection {
                let norm = sel.normalized
                storage.delete(range: norm, undoManager: undoManager)
                cursorPosition = norm.start
                selection = nil
            } else {
                guard cursorPosition != TextStorage.Position(line: 0, column: 0) else { return }
                let deleteStart: TextStorage.Position
                if cursorPosition.column > 0 {
                    deleteStart = TextStorage.Position(line: cursorPosition.line, column: cursorPosition.column - 1)
                } else {
                    let prevLine = cursorPosition.line - 1
                    deleteStart = TextStorage.Position(line: prevLine, column: storage.lineLength(prevLine))
                }
                storage.delete(range: TextStorage.Range(start: deleteStart, end: cursorPosition), undoManager: undoManager)
                cursorPosition = deleteStart
            }
        }
        needsRenderCallback?()
    }

    func deleteForward() {
        withUndoGroup {
            if let sel = selection {
                let norm = sel.normalized
                storage.delete(range: norm, undoManager: undoManager)
                cursorPosition = norm.start
                selection = nil
            } else {
                let lastLine = storage.lineCount - 1
                let endPos = TextStorage.Position(line: lastLine, column: storage.lineLength(lastLine))
                guard cursorPosition != endPos else { return }
                let deleteEnd: TextStorage.Position
                if cursorPosition.column < storage.lineLength(cursorPosition.line) {
                    deleteEnd = TextStorage.Position(line: cursorPosition.line, column: cursorPosition.column + 1)
                } else {
                    deleteEnd = TextStorage.Position(line: cursorPosition.line + 1, column: 0)
                }
                storage.delete(range: TextStorage.Range(start: cursorPosition, end: deleteEnd), undoManager: undoManager)
            }
        }
        needsRenderCallback?()
    }

    func insertNewline() {
        insertText("\n")
    }

    func insertTab() {
        insertText("    ")  // 4 spaces
    }

    // MARK: - Selection

    func selectAll() {
        let lastLine = storage.lineCount - 1
        selection = TextStorage.Range(
            start: TextStorage.Position(line: 0, column: 0),
            end: TextStorage.Position(line: lastLine, column: storage.lineLength(lastLine))
        )
        cursorPosition = selection!.end
        needsRenderCallback?()
    }

    func selectedText() -> String? {
        guard let sel = selection else { return nil }
        let norm = sel.normalized
        guard !norm.isEmpty else { return nil }
        return storage.textInRange(norm)
    }

    // MARK: - Clipboard

    func copy() {
        guard let text = selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        insertText(text)
    }

    func cut() {
        copy()
        if let sel = selection {
            withUndoGroup {
                let norm = sel.normalized
                storage.delete(range: norm, undoManager: undoManager)
                cursorPosition = norm.start
                selection = nil
            }
            needsRenderCallback?()
        }
    }

    // MARK: - Undo/Redo

    func undo() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        needsRenderCallback?()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        needsRenderCallback?()
    }

    // MARK: - View Lifecycle

    func createView(theme: TerminalTheme, fontFamily: String, fontSize: Double) {
        guard editorView == nil else { return }
        let view = EditorView(session: self, theme: theme, fontFamily: fontFamily, fontSize: CGFloat(fontSize))
        editorView = view
    }

    func updateTheme(_ theme: TerminalTheme) {
        (editorView as? EditorView)?.updateTheme(theme)
    }

    func updateFont(family: String, size: Double) {
        (editorView as? EditorView)?.updateFont(family: family, size: CGFloat(size))
    }
}
