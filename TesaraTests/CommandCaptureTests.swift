import XCTest
import GRDB
@testable import Tesara

@MainActor
final class CommandCaptureTests: XCTestCase {
    private var session: TerminalSession!

    override func setUp() {
        super.setUp()
        session = TerminalSession()
    }

    override func tearDown() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
    }

    /// Configures the session with a block store and calls start() to set up activeSessionID.
    /// start() will fail to create a surface (no ghostty app in tests) but activeSessionID is set.
    private func startSession(blockStore: BlockStore) {
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
    }

    // MARK: - readAndCleanupCommandFile

    func testReadAndCleanupReturnsFileContent() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "echo hello".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "echo hello")
    }

    func testReadAndCleanupRemovesFile() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "ls -la".write(toFile: path, atomically: true, encoding: .utf8)

        _ = session.readAndCleanupCommandFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testReadAndCleanupReturnsNilForMissingFile() {
        let result = session.readAndCleanupCommandFile()
        XCTAssertNil(result)
    }

    func testReadAndCleanupReturnsRawContent() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "  git status  \n".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "  git status  \n")
    }

    func testReadAndCleanupReturnsWhitespaceContent() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "   \n  ".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "   \n  ")
    }

    // MARK: - handleCommandFinished

    func testHandleCommandFinishedWithTempFile() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "echo test".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 0, durationNs: 500_000_000)

        XCTAssertEqual(session.capturedBlockCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testHandleCommandFinishedWithoutTempFileDoesNotCapture() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        session.handleCommandFinished(exitCode: 0, durationNs: 100_000_000)

        XCTAssertEqual(session.capturedBlockCount, 0)
    }

    func testHandleCommandFinishedWithEmptyCommandDoesNotCapture() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "   \n  ".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 0, durationNs: 100_000_000)

        XCTAssertEqual(session.capturedBlockCount, 0)
    }

    func testHandleCommandFinishedWithNonZeroExitCode() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "false".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 1, durationNs: 10_000_000)

        XCTAssertEqual(session.capturedBlockCount, 1)
    }

    func testHandleCommandFinishedWithExitCodeNegativeOneTreatsAsNil() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "interrupted-cmd".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: -1, durationNs: 10_000_000)

        XCTAssertEqual(session.capturedBlockCount, 1)
    }

    func testMultipleCommandFinishedIncrementsCaptureCount() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"

        for i in 0..<3 {
            try "cmd\(i)".write(toFile: path, atomically: true, encoding: .utf8)
            session.handleCommandFinished(exitCode: 0, durationNs: UInt64(i * 100_000_000))
        }

        XCTAssertEqual(session.capturedBlockCount, 3)
    }

    // MARK: - handleChildExited

    func testHandleChildExitedTransitionsToStopped() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSession(blockStore: blockStore)
        session.handleChildExited(exitCode: 0)
        XCTAssertEqual(session.status, .stopped)
    }
}
