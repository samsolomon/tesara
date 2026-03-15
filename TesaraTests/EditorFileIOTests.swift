import XCTest
@testable import Tesara

@MainActor
final class EditorFileIOTests: XCTestCase {
    private var session: EditorSession!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        session = EditorSession()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func tempFile(name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Load File

    func testLoadFilePopulatesStorage() throws {
        let url = try tempFile(name: "test.txt", content: "hello\nworld")
        try session.loadFile(url: url)
        XCTAssertEqual(session.storage.lineCount, 2)
        XCTAssertEqual(session.storage.lineContent(0), "hello")
        XCTAssertEqual(session.storage.lineContent(1), "world")
    }

    func testLoadFileSetsPath() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        XCTAssertEqual(session.filePath, url)
    }

    func testLoadFileIsNotDirty() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        XCTAssertFalse(session.isDirty)
    }

    func testLoadFileResetsCursor() throws {
        session.insertText("some text")
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        XCTAssertEqual(session.cursorPosition, TextStorage.Position(line: 0, column: 0))
    }

    func testLoadFileClearsSelection() throws {
        session.insertText("some text")
        session.selectAll()
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        XCTAssertNil(session.selection)
    }

    // MARK: - CRLF Normalization

    func testCRLFNormalizedToLF() throws {
        let url = tempDir.appendingPathComponent("crlf.txt")
        try "line1\r\nline2\r\nline3".write(to: url, atomically: true, encoding: .utf8)
        try session.loadFile(url: url)
        XCTAssertEqual(session.storage.lineCount, 3)
        XCTAssertEqual(session.storage.lineContent(0), "line1")
        XCTAssertEqual(session.storage.lineContent(1), "line2")
        XCTAssertEqual(session.storage.lineContent(2), "line3")
        // Verify no \r in the stored content
        XCTAssertFalse(session.storage.entireString().contains("\r"))
    }

    // MARK: - File Size Guard

    func testFileTooLargeThrows() throws {
        let url = tempDir.appendingPathComponent("large.txt")
        let largeData = Data(repeating: 0x41, count: 6 * 1024 * 1024) // 6 MB
        try largeData.write(to: url)
        XCTAssertThrowsError(try session.loadFile(url: url)) { error in
            guard case EditorFileError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: - Save

    func testSaveWritesContent() throws {
        let url = try tempFile(name: "save.txt", content: "original")
        try session.loadFile(url: url)
        session.insertText(" modified")
        try session.save()
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(saved.contains("modified"))
    }

    func testSaveClearsDirtyFlag() throws {
        let url = try tempFile(name: "save.txt", content: "hello")
        try session.loadFile(url: url)
        session.insertText("!")
        XCTAssertTrue(session.isDirty)
        try session.save()
        XCTAssertFalse(session.isDirty)
    }

    func testSaveWithoutPathThrows() {
        session.insertText("hello")
        XCTAssertThrowsError(try session.save()) { error in
            guard case EditorFileError.noFilePath = error else {
                XCTFail("Expected noFilePath, got \(error)")
                return
            }
        }
    }

    // MARK: - Save As

    func testSaveAsChangesPath() throws {
        session.insertText("hello")
        let url = tempDir.appendingPathComponent("newfile.txt")
        try session.saveAs(url: url)
        XCTAssertEqual(session.filePath, url)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "hello")
    }

    // MARK: - Dirty Tracking with Undo

    func testDirtyAfterInsert() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        session.insertText("!")
        XCTAssertTrue(session.isDirty)
    }

    func testDirtyClearsAfterUndoBackToSavedContents() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        session.insertText("!")
        XCTAssertTrue(session.isDirty)

        session.undo()

        XCTAssertFalse(session.isDirty)
    }

    func testDirtyAfterUndoPastSavePoint() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        session.insertText("!")
        try session.save()
        XCTAssertFalse(session.isDirty)
        session.undo()
        XCTAssertTrue(session.isDirty, "Should be dirty after undoing past save point")
    }

    // MARK: - Display Title

    func testDisplayTitleUntitled() {
        XCTAssertEqual(session.displayTitle, "Untitled")
    }

    func testDisplayTitleShowsFilename() throws {
        let url = try tempFile(name: "myfile.swift", content: "import Foundation")
        try session.loadFile(url: url)
        XCTAssertEqual(session.displayTitle, "myfile.swift")
    }

    func testDisplayTitleShowsDirtyPrefix() throws {
        let url = try tempFile(name: "myfile.swift", content: "import Foundation")
        try session.loadFile(url: url)
        session.insertText("// comment\n")
        XCTAssertEqual(session.displayTitle, "● myfile.swift")
    }

    // MARK: - Stale Detection

    func testCheckFileStaleDetectsExternalModification() throws {
        let url = try tempFile(name: "stale.txt", content: "original")
        try session.loadFile(url: url)

        // Simulate external modification by writing to the file after a brief delay
        // Force a different modification date
        Thread.sleep(forTimeInterval: 0.1)
        try "modified externally".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertTrue(session.checkFileStale())
    }

    func testCheckFileStaleReturnsFalseWhenUnmodified() throws {
        let url = try tempFile(name: "stale.txt", content: "original")
        try session.loadFile(url: url)
        XCTAssertFalse(session.checkFileStale())
    }

    // MARK: - Syntax Highlighting

    func testEditingRetokenizesSyntaxHighlighting() throws {
        let url = try tempFile(name: "token.swift", content: "value")
        try session.loadFile(url: url)

        session.insertText("let ")

        let line = session.storage.lineContent(0)
        let keywordToken = session.syntaxHighlighter?
            .tokens(forLine: 0)?
            .first(where: { $0.kind == .keyword })

        XCTAssertEqual(extractText(line, token: keywordToken), "let")
    }

    // MARK: - Word Wrap

    func testWordWrapRecomputesAfterDocumentChange() {
        session.createView(theme: testTheme, fontFamily: "Menlo", fontSize: 13)
        session.wordWrapEnabled = true

        let editorView = session.editorView as! EditorView
        editorView.sizeDidChange(CGSize(width: 120, height: 240))
        XCTAssertEqual(editorView.totalVisualLinesForTesting(), 1)

        session.insertText(String(repeating: "abcdefghij ", count: 20))

        XCTAssertGreaterThan(editorView.totalVisualLinesForTesting(), 1)
    }

    // MARK: - Encoding Error

    func testNonUTF8FileThrowsEncodingError() throws {
        let url = tempDir.appendingPathComponent("binary.txt")
        // Write raw bytes that are not valid UTF-8
        let invalidUTF8 = Data([0xFF, 0xFE, 0x80, 0x81, 0x82])
        try invalidUTF8.write(to: url)
        XCTAssertThrowsError(try session.loadFile(url: url)) { error in
            guard case EditorFileError.encodingError = error else {
                XCTFail("Expected encodingError, got \(error)")
                return
            }
        }
    }

    // MARK: - File at Exactly Max Size

    func testFileAtExactlyMaxSizeLoadsSuccessfully() throws {
        let url = tempDir.appendingPathComponent("exact.txt")
        let content = String(repeating: "A", count: EditorSession.maxFileSize)
        try content.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try session.loadFile(url: url))
    }

    // MARK: - Syntax Highlighter Setup

    func testLoadSwiftFileSetsUpSyntaxHighlighter() throws {
        let url = try tempFile(name: "test.swift", content: "let x = 1")
        try session.loadFile(url: url)
        XCTAssertNotNil(session.syntaxHighlighter)
    }

    func testLoadJSONFileSetsUpSyntaxHighlighter() throws {
        let url = try tempFile(name: "data.json", content: "{\"key\": 1}")
        try session.loadFile(url: url)
        XCTAssertNotNil(session.syntaxHighlighter)
    }

    func testLoadPlainTextHasInactiveSyntaxHighlighter() throws {
        let url = try tempFile(name: "readme.txt", content: "Hello world")
        try session.loadFile(url: url)
        // SyntaxHighlighter is created but tokenizer is nil for unknown extensions
        XCTAssertNotNil(session.syntaxHighlighter)
        XCTAssertFalse(session.syntaxHighlighter?.isActive ?? true)
    }

    // MARK: - Load Clears Undo Stack

    func testLoadFileClearsUndoStack() throws {
        session.insertText("some text")
        XCTAssertTrue(session.undoManager.canUndo)

        let url = try tempFile(name: "test.txt", content: "fresh")
        try session.loadFile(url: url)
        XCTAssertFalse(session.undoManager.canUndo)
    }

    // MARK: - Save As Sets Up Syntax Highlighting

    func testSaveAsToSwiftExtensionEnablesSyntaxHighlighting() throws {
        session.insertText("let x = 1")
        XCTAssertNil(session.syntaxHighlighter)

        let url = tempDir.appendingPathComponent("new.swift")
        try session.saveAs(url: url)
        XCTAssertNotNil(session.syntaxHighlighter)
    }

    // MARK: - Modification Date Tracking

    func testLoadFileSetsModificationDate() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        XCTAssertNotNil(session.fileModificationDate)
    }

    func testSaveUpdatesModificationDate() throws {
        let url = try tempFile(name: "test.txt", content: "hello")
        try session.loadFile(url: url)
        let originalDate = session.fileModificationDate

        Thread.sleep(forTimeInterval: 0.1)
        session.insertText("!")
        try session.save()

        XCTAssertNotEqual(session.fileModificationDate, originalDate)
    }

    // MARK: - Stale Detection Edge Cases

    func testCheckFileStaleWithNoPathReturnsFalse() {
        XCTAssertFalse(session.checkFileStale())
    }

    // MARK: - Error Descriptions

    func testFileTooLargeErrorDescription() {
        let error = EditorFileError.fileTooLarge(10 * 1024 * 1024)
        XCTAssertTrue(error.errorDescription?.contains("10.0 MB") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("5 MB") ?? false)
    }

    func testEncodingErrorDescription() {
        let error = EditorFileError.encodingError
        XCTAssertTrue(error.errorDescription?.contains("UTF-8") ?? false)
    }

    func testNoFilePathErrorDescription() {
        let error = EditorFileError.noFilePath
        XCTAssertTrue(error.errorDescription?.contains("Save As") ?? false)
    }

    private func extractText(_ line: String, token: SyntaxToken?) -> String? {
        guard let token else { return nil }
        let utf16 = Array(line.utf16)
        let slice = Array(utf16[token.range])
        return String(decoding: slice, as: UTF16.self)
    }

    private var testTheme: TerminalTheme {
        TerminalTheme(
            id: "test", name: "Test",
            foreground: "#cccccc", background: "#1e1e1e",
            cursor: "#cccccc", cursorText: "#1e1e1e",
            selectionBackground: "#3c5a96",
            black: "#000000", red: "#ff0000", green: "#00ff00",
            yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
            cyan: "#00ffff", white: "#ffffff",
            brightBlack: "#808080", brightRed: "#ff0000",
            brightGreen: "#00ff00", brightYellow: "#ffff00",
            brightBlue: "#0000ff", brightMagenta: "#ff00ff",
            brightCyan: "#00ffff", brightWhite: "#ffffff"
        )
    }
}
