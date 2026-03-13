import XCTest
@testable import Tesara

@MainActor
final class TextStorageTests: XCTestCase {
    private var storage: TextStorage!

    override func setUp() async throws {
        try await super.setUp()
        storage = TextStorage()
    }

    // MARK: - Initial State

    func testInitialStateHasOneLine() {
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "")
        XCTAssertEqual(storage.lineLength(0), 0)
    }

    func testEntireStringEmptyByDefault() {
        XCTAssertEqual(storage.entireString(), "")
    }

    // MARK: - Load String

    func testLoadStringSingleLine() {
        storage.loadString("hello")
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "hello")
    }

    func testLoadStringMultiLine() {
        storage.loadString("line1\nline2\nline3")
        XCTAssertEqual(storage.lineCount, 3)
        XCTAssertEqual(storage.lineContent(0), "line1")
        XCTAssertEqual(storage.lineContent(1), "line2")
        XCTAssertEqual(storage.lineContent(2), "line3")
    }

    func testLoadStringTrailingNewline() {
        storage.loadString("hello\n")
        XCTAssertEqual(storage.lineCount, 2)
        XCTAssertEqual(storage.lineContent(0), "hello")
        XCTAssertEqual(storage.lineContent(1), "")
    }

    func testLoadStringEmpty() {
        storage.loadString("")
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "")
    }

    func testEntireStringRoundTrip() {
        let text = "line1\nline2\nline3"
        storage.loadString(text)
        XCTAssertEqual(storage.entireString(), text)
    }

    // MARK: - Insert

    func testInsertAtBeginning() {
        let pos = storage.insert("hello", at: .init(line: 0, column: 0), undoManager: nil)
        XCTAssertEqual(storage.lineContent(0), "hello")
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 5))
    }

    func testInsertInMiddle() {
        storage.loadString("helo")
        let pos = storage.insert("l", at: .init(line: 0, column: 3), undoManager: nil)
        XCTAssertEqual(storage.lineContent(0), "hello")
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 4))
    }

    func testInsertNewlineSplitsLine() {
        storage.loadString("helloworld")
        let pos = storage.insert("\n", at: .init(line: 0, column: 5), undoManager: nil)
        XCTAssertEqual(storage.lineCount, 2)
        XCTAssertEqual(storage.lineContent(0), "hello")
        XCTAssertEqual(storage.lineContent(1), "world")
        XCTAssertEqual(pos, TextStorage.Position(line: 1, column: 0))
    }

    func testInsertMultipleNewlines() {
        storage.loadString("ab")
        storage.insert("\n\n", at: .init(line: 0, column: 1), undoManager: nil)
        XCTAssertEqual(storage.lineCount, 3)
        XCTAssertEqual(storage.lineContent(0), "a")
        XCTAssertEqual(storage.lineContent(1), "")
        XCTAssertEqual(storage.lineContent(2), "b")
    }

    func testInsertMultiLineText() {
        storage.loadString("start end")
        let pos = storage.insert("line1\nline2\nline3", at: .init(line: 0, column: 6), undoManager: nil)
        XCTAssertEqual(storage.lineCount, 3)
        XCTAssertEqual(storage.lineContent(0), "start line1")
        XCTAssertEqual(storage.lineContent(1), "line2")
        XCTAssertEqual(storage.lineContent(2), "line3end")
        XCTAssertEqual(pos, TextStorage.Position(line: 2, column: 5))
    }

    // MARK: - Delete

    func testDeleteSingleCharacter() {
        storage.loadString("hello")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 1),
            end: .init(line: 0, column: 2)
        )
        let deleted = storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(deleted, "e")
        XCTAssertEqual(storage.lineContent(0), "hllo")
    }

    func testDeleteAcrossLines() {
        storage.loadString("hello\nworld")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 3),
            end: .init(line: 1, column: 2)
        )
        let deleted = storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(deleted, "lo\nwo")
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "helrld")
    }

    func testDeleteAtLineStart_JoinsLines() {
        storage.loadString("hello\nworld")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 5),
            end: .init(line: 1, column: 0)
        )
        storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "helloworld")
    }

    func testDeleteEmptyRange() {
        storage.loadString("hello")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 2),
            end: .init(line: 0, column: 2)
        )
        let deleted = storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(deleted, "")
        XCTAssertEqual(storage.lineContent(0), "hello")
    }

    func testDeleteMultipleMiddleLines() {
        storage.loadString("aaa\nbbb\nccc\nddd")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 2),
            end: .init(line: 3, column: 1)
        )
        let deleted = storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(deleted, "a\nbbb\nccc\nd")
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "aadd")
    }

    // MARK: - Replace

    func testReplaceSingleLine() {
        storage.loadString("hello world")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 6),
            end: .init(line: 0, column: 11)
        )
        let pos = storage.replace(range: range, with: "Swift", undoManager: nil)
        XCTAssertEqual(storage.lineContent(0), "hello Swift")
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 11))
    }

    func testReplaceWithMultiLine() {
        storage.loadString("AB")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 1),
            end: .init(line: 0, column: 1)
        )
        let pos = storage.replace(range: range, with: "\n\n", undoManager: nil)
        XCTAssertEqual(storage.lineCount, 3)
        XCTAssertEqual(storage.lineContent(0), "A")
        XCTAssertEqual(storage.lineContent(1), "")
        XCTAssertEqual(storage.lineContent(2), "B")
        XCTAssertEqual(pos, TextStorage.Position(line: 2, column: 0))
    }

    // MARK: - Undo/Redo

    func testUndoInsert() {
        let undoManager = UndoManager()
        storage.insert("hello", at: .init(line: 0, column: 0), undoManager: undoManager)
        XCTAssertEqual(storage.lineContent(0), "hello")

        undoManager.undo()
        XCTAssertEqual(storage.lineContent(0), "")
    }

    func testUndoDelete() {
        let undoManager = UndoManager()
        storage.loadString("hello")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 1),
            end: .init(line: 0, column: 4)
        )
        storage.delete(range: range, undoManager: undoManager)
        XCTAssertEqual(storage.lineContent(0), "ho")

        undoManager.undo()
        XCTAssertEqual(storage.lineContent(0), "hello")
    }

    func testUndoReplace() {
        let undoManager = UndoManager()
        storage.loadString("hello")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 0),
            end: .init(line: 0, column: 5)
        )
        storage.replace(range: range, with: "world", undoManager: undoManager)
        XCTAssertEqual(storage.lineContent(0), "world")

        undoManager.undo()
        XCTAssertEqual(storage.lineContent(0), "hello")
    }

    func testRedoAfterUndo() {
        let undoManager = UndoManager()
        storage.insert("hello", at: .init(line: 0, column: 0), undoManager: undoManager)
        undoManager.undo()
        XCTAssertEqual(storage.lineContent(0), "")

        undoManager.redo()
        XCTAssertEqual(storage.lineContent(0), "hello")
    }

    func testUndoMultiLineInsert() {
        let undoManager = UndoManager()
        storage.loadString("AB")
        storage.insert("\nC\n", at: .init(line: 0, column: 1), undoManager: undoManager)
        XCTAssertEqual(storage.lineCount, 3)

        undoManager.undo()
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "AB")
    }

    func testUndoMultiLineDelete() {
        let undoManager = UndoManager()
        storage.loadString("aaa\nbbb\nccc")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 1),
            end: .init(line: 2, column: 1)
        )
        storage.delete(range: range, undoManager: undoManager)
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "acc")

        undoManager.undo()
        XCTAssertEqual(storage.lineCount, 3)
        XCTAssertEqual(storage.entireString(), "aaa\nbbb\nccc")
    }

    // MARK: - Word Boundary

    func testWordBoundaryRight() {
        storage.loadString("hello world")
        let pos = storage.wordBoundary(from: .init(line: 0, column: 0), direction: .right)
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 6))
    }

    func testWordBoundaryLeft() {
        storage.loadString("hello world")
        let pos = storage.wordBoundary(from: .init(line: 0, column: 11), direction: .left)
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 6))
    }

    func testWordBoundaryRightAtEndOfLine() {
        storage.loadString("hello\nworld")
        let pos = storage.wordBoundary(from: .init(line: 0, column: 5), direction: .right)
        XCTAssertEqual(pos, TextStorage.Position(line: 1, column: 0))
    }

    func testWordBoundaryLeftAtStartOfLine() {
        storage.loadString("hello\nworld")
        let pos = storage.wordBoundary(from: .init(line: 1, column: 0), direction: .left)
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 5))
    }

    func testWordBoundaryWithPunctuation() {
        storage.loadString("foo.bar")
        let pos = storage.wordBoundary(from: .init(line: 0, column: 0), direction: .right)
        // Should stop at punctuation boundary
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 3))
    }

    // MARK: - Clamp Position

    func testClampPositionBeyondEnd() {
        storage.loadString("hi")
        let clamped = storage.clampPosition(.init(line: 5, column: 100))
        XCTAssertEqual(clamped, TextStorage.Position(line: 0, column: 2))
    }

    func testClampPositionNegative() {
        storage.loadString("hi")
        let clamped = storage.clampPosition(.init(line: -1, column: -1))
        XCTAssertEqual(clamped, TextStorage.Position(line: 0, column: 0))
    }

    // MARK: - Unicode

    func testUnicodeMultiByte() {
        storage.loadString("café")
        // 'é' is single UTF-16 code unit (U+00E9)
        XCTAssertEqual(storage.lineLength(0), 4)
        storage.insert("!", at: .init(line: 0, column: 4), undoManager: nil)
        XCTAssertEqual(storage.lineContent(0), "café!")
    }

    func testUnicodeEmoji() {
        // 😀 is U+1F600, encoded as surrogate pair in UTF-16 (2 code units)
        storage.loadString("a😀b")
        XCTAssertEqual(storage.lineLength(0), 4) // a(1) + 😀(2) + b(1) = 4
    }

    func testDeleteReversedRange() {
        storage.loadString("hello")
        // Reversed range: end < start — should still work via normalization
        let range = TextStorage.Range(
            start: .init(line: 0, column: 3),
            end: .init(line: 0, column: 1)
        )
        let deleted = storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(deleted, "el")
        XCTAssertEqual(storage.lineContent(0), "hlo")
    }

    // MARK: - Edge Cases

    func testInsertIntoEmptyBuffer() {
        let pos = storage.insert("x", at: .init(line: 0, column: 0), undoManager: nil)
        XCTAssertEqual(storage.lineContent(0), "x")
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 1))
    }

    func testDeleteEntireContent() {
        storage.loadString("hello\nworld")
        let range = TextStorage.Range(
            start: .init(line: 0, column: 0),
            end: .init(line: 1, column: 5)
        )
        storage.delete(range: range, undoManager: nil)
        XCTAssertEqual(storage.lineCount, 1)
        XCTAssertEqual(storage.lineContent(0), "")
    }

    func testLineContentOutOfBounds() {
        XCTAssertEqual(storage.lineContent(-1), "")
        XCTAssertEqual(storage.lineContent(100), "")
    }

    func testLineLengthOutOfBounds() {
        XCTAssertEqual(storage.lineLength(-1), 0)
        XCTAssertEqual(storage.lineLength(100), 0)
    }
}
