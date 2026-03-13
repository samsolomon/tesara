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
}
