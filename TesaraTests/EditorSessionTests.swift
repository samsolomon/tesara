import XCTest
@testable import Tesara

@MainActor
final class EditorSessionTests: XCTestCase {
    private var session: EditorSession!

    override func setUp() async throws {
        try await super.setUp()
        session = EditorSession()
    }

    // MARK: - Initial State

    func testInitialCursorAtOrigin() {
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testInitialSelectionIsNil() {
        XCTAssertNil(session.selection)
    }

    // MARK: - Cursor Movement

    func testMoveRight() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        session.moveCursor(.right)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 1))
    }

    func testMoveLeft() {
        session.insertText("hello")
        session.moveCursor(.left)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 4))
    }

    func testMoveLeftAtOriginStays() {
        session.moveCursor(.left)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testMoveDown() {
        session.insertText("hello\nworld")
        session.moveCursor(.documentStart)
        session.moveCursor(.down)
        XCTAssertEqual(session.cursorPosition.line, 1)
    }

    func testMoveUp() {
        session.insertText("hello\nworld")
        session.moveCursor(.up)
        XCTAssertEqual(session.cursorPosition.line, 0)
    }

    func testMoveUpClampsColumn() {
        session.insertText("hi\nhello")
        // Cursor at (1, 5). Move up to line 0 which has length 2.
        session.moveCursor(.up)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 2))
    }

    func testMoveWordRight() {
        session.insertText("hello world")
        session.moveCursor(.lineStart)
        session.moveCursor(.wordRight)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 6))
    }

    func testMoveWordLeft() {
        session.insertText("hello world")
        session.moveCursor(.wordLeft)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 6))
    }

    func testMoveLineStart() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testMoveLineEnd() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        session.moveCursor(.lineEnd)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 5))
    }

    func testMoveDocumentStart() {
        session.insertText("hello\nworld")
        session.moveCursor(.documentStart)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testMoveDocumentEnd() {
        session.insertText("hello\nworld")
        session.moveCursor(.documentStart)
        session.moveCursor(.documentEnd)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 1, column: 5))
    }

    // MARK: - Selection

    func testExtendSelectionRight() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right, extending: true)
        XCTAssertNotNil(session.selection)
        let sel = session.selection!.normalized
        XCTAssertEqual(sel.start, TextStorage.Position(line: 0, column: 0))
        XCTAssertEqual(sel.end, TextStorage.Position(line: 0, column: 2))
    }

    func testMoveClearsSel() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right) // without extending
        XCTAssertNil(session.selection)
    }

    func testSelectAll() {
        session.insertText("hello\nworld")
        session.selectAll()
        let sel = session.selection!.normalized
        XCTAssertEqual(sel.start, TextStorage.Position(line: 0, column: 0))
        XCTAssertEqual(sel.end, TextStorage.Position(line: 1, column: 5))
    }

    func testSelectedText() {
        session.insertText("hello world")
        session.moveCursor(.lineStart)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right, extending: true)
        session.moveCursor(.right, extending: true)
        XCTAssertEqual(session.selectedText(), "hello")
    }

    func testSelectedTextNilWhenNoSelection() {
        session.insertText("hello")
        XCTAssertNil(session.selectedText())
    }

    // MARK: - Selection Collapse on Move

    func testMoveLeftCollapsesSelectionToStart() {
        session.insertText("hello")
        session.selectAll()
        session.moveCursor(.left)
        XCTAssertNil(session.selection)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testMoveRightCollapsesSelectionToEnd() {
        session.insertText("hello")
        session.selectAll()
        session.moveCursor(.right)
        XCTAssertNil(session.selection)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 5))
    }

    // MARK: - Text Input

    func testInsertText() {
        session.insertText("hello")
        XCTAssertEqual(session.storage.entireString(), "hello")
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 5))
    }

    func testInsertTextReplacesSelection() {
        session.insertText("hello")
        session.selectAll()
        session.insertText("bye")
        XCTAssertEqual(session.storage.entireString(), "bye")
        XCTAssertNil(session.selection)
    }

    func testInsertNewline() {
        session.insertText("hello")
        session.insertNewline()
        XCTAssertEqual(session.storage.lineCount, 2)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 1, column: 0))
    }

    func testInsertTab() {
        session.insertTab()
        XCTAssertEqual(session.storage.lineContent(0), "    ")
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 4))
    }

    // MARK: - Delete

    func testDeleteBackward() {
        session.insertText("hello")
        session.deleteBackward()
        XCTAssertEqual(session.storage.entireString(), "hell")
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 4))
    }

    func testDeleteBackwardAtOriginIsNoOp() {
        session.deleteBackward()
        XCTAssertEqual(session.storage.entireString(), "")
    }

    func testDeleteBackwardJoinsLines() {
        session.insertText("hello\nworld")
        session.moveCursor(.lineStart) // now at (1, 0)
        session.deleteBackward()
        XCTAssertEqual(session.storage.lineCount, 1)
        XCTAssertEqual(session.storage.lineContent(0), "helloworld")
    }

    func testDeleteBackwardWithSelection() {
        session.insertText("hello world")
        session.selectAll()
        session.deleteBackward()
        XCTAssertEqual(session.storage.entireString(), "")
        XCTAssertNil(session.selection)
    }

    func testDeleteForward() {
        session.insertText("hello")
        session.moveCursor(.lineStart)
        session.deleteForward()
        XCTAssertEqual(session.storage.entireString(), "ello")
    }

    func testDeleteForwardAtEndIsNoOp() {
        session.insertText("hi")
        session.deleteForward()
        XCTAssertEqual(session.storage.entireString(), "hi")
    }

    func testDeleteForwardJoinsLines() {
        session.insertText("hello\nworld")
        session.moveCursor(.lineStart) // (1, 0)
        session.moveCursor(.up) // (0, 0)
        session.moveCursor(.lineEnd) // (0, 5)
        session.deleteForward()
        XCTAssertEqual(session.storage.lineCount, 1)
        XCTAssertEqual(session.storage.lineContent(0), "helloworld")
    }

    // MARK: - Undo/Redo

    func testUndoInsert() {
        session.insertText("hello")
        session.undo()
        XCTAssertEqual(session.storage.entireString(), "")
    }

    func testRedoInsert() {
        session.insertText("hello")
        session.undo()
        session.redo()
        XCTAssertEqual(session.storage.entireString(), "hello")
    }

    func testUndoDelete() {
        session.insertText("hello")
        session.deleteBackward()
        session.undo()
        XCTAssertEqual(session.storage.entireString(), "hello")
    }

    // MARK: - Clipboard

    func testCopyPasteRoundTrip() {
        session.insertText("hello world")
        session.selectAll()
        session.copy()
        session.moveCursor(.documentEnd)
        session.insertNewline()
        session.paste()
        XCTAssertEqual(session.storage.lineContent(1), "hello world")
    }

    func testCut() {
        session.insertText("hello")
        session.selectAll()
        session.cut()
        XCTAssertEqual(session.storage.entireString(), "")
        XCTAssertNil(session.selection)
        // Paste should bring it back
        session.paste()
        XCTAssertEqual(session.storage.entireString(), "hello")
    }

    // MARK: - Move Right/Left Wrap

    func testMoveRightWrapsToNextLine() {
        session.insertText("ab\ncd")
        // Position at end of line 0
        session.moveCursor(.documentStart)
        session.moveCursor(.lineEnd) // (0, 2)
        session.moveCursor(.right) // should go to (1, 0)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 1, column: 0))
    }

    func testMoveLeftWrapsToPreviousLine() {
        session.insertText("ab\ncd")
        session.moveCursor(.documentStart)
        session.moveCursor(.down) // (1, 0)
        session.moveCursor(.left) // should go to (0, 2)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 2))
    }
}
