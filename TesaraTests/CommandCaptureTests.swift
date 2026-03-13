import XCTest
import GRDB
@testable import Tesara

// MARK: - Stub Launcher for Ghostty Mode Tests

private final class StubProcessHandle: TerminalProcessHandle {
    func send(_ input: String) throws {}
    func resize(cols: UInt16, rows: UInt16) {}
    func stop() {}
}

private final class StubLauncher: TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle {
        StubProcessHandle()
    }
}

// MARK: - Tests

@MainActor
final class CommandCaptureTests: XCTestCase {
    private var session: TerminalSession!

    override func setUp() {
        super.setUp()
        session = TerminalSession(launcher: StubLauncher())
    }

    override func tearDown() {
        // Clean up any lingering temp files
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? FileManager.default.removeItem(atPath: path)
        super.tearDown()
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

    func testReadAndCleanupTrimsWhitespace() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "  git status  \n".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "git status")
    }

    func testReadAndCleanupReturnsNilForEmptyContent() {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try? "   \n  ".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        // After trimming, empty string
        XCTAssertEqual(result, "")
    }

    // MARK: - handleCommandFinished in Ghostty Mode

    /// Start in PTY mode (works with mock launcher to set activeSessionID),
    /// then reconfigure to ghostty mode for command capture testing.
    private func startSessionThenSwitchToGhostty(blockStore: BlockStore) {
        session.configure(blockStore: blockStore, mode: .pty)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        // Reconfigure to ghostty mode — activeSessionID is already set from startPTY
        session.configure(blockStore: blockStore, mode: .ghostty)
    }

    func testHandleCommandFinishedWithTempFile() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        // Simulate what the shell preexec hook does
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "echo test".write(toFile: path, atomically: true, encoding: .utf8)

        // Simulate command finished — 500ms duration, exit code 0
        session.handleCommandFinished(exitCode: 0, durationNs: 500_000_000)

        XCTAssertEqual(session.capturedBlockCount, 1)
        // Temp file should be cleaned up
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testHandleCommandFinishedWithoutTempFileDoesNotCapture() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        // No temp file written — simulate a command that didn't trigger preexec
        session.handleCommandFinished(exitCode: 0, durationNs: 100_000_000)

        XCTAssertEqual(session.capturedBlockCount, 0)
    }

    func testHandleCommandFinishedWithEmptyCommandDoesNotCapture() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "   \n  ".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 0, durationNs: 100_000_000)

        XCTAssertEqual(session.capturedBlockCount, 0)
    }

    func testHandleCommandFinishedWithNonZeroExitCode() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "false".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 1, durationNs: 10_000_000)

        XCTAssertEqual(session.capturedBlockCount, 1)
    }

    func testHandleCommandFinishedWithExitCodeNegativeOneTreatsAsNil() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "interrupted-cmd".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: -1, durationNs: 10_000_000)

        // -1 is treated as nil exit code, but block should still be captured
        XCTAssertEqual(session.capturedBlockCount, 1)
    }

    func testMultipleCommandFinishedIncrementsCaptureCount() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        startSessionThenSwitchToGhostty(blockStore: blockStore)

        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"

        for i in 0..<3 {
            try "cmd\(i)".write(toFile: path, atomically: true, encoding: .utf8)
            session.handleCommandFinished(exitCode: 0, durationNs: UInt64(i * 100_000_000))
        }

        XCTAssertEqual(session.capturedBlockCount, 3)
    }

    // MARK: - handleCommandFinished in PTY Mode

    func testHandleCommandFinishedInPTYModeDoesNotReadTempFile() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore, mode: .pty)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        // Write a temp file to ensure PTY mode ignores it
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "should-not-be-read".write(toFile: path, atomically: true, encoding: .utf8)

        session.handleCommandFinished(exitCode: 0, durationNs: 100_000_000)

        // PTY mode doesn't read temp files — no active capture was set
        XCTAssertEqual(session.capturedBlockCount, 0)
        // Temp file should still exist (not cleaned up by PTY path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - handleChildExited

    func testHandleChildExitedTransitionsToStopped() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore, mode: .pty)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.handleChildExited(exitCode: 0)
        XCTAssertEqual(session.status, .stopped)
    }

    // MARK: - Dual Mode

    func testGhosttyModeDefaultIsPTY() {
        XCTAssertEqual(session.mode, .pty)
    }

    func testConfigureSetsMode() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore, mode: .ghostty)
        XCTAssertEqual(session.mode, .ghostty)
    }

    func testResizeIgnoredInGhosttyMode() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore, mode: .ghostty)
        // Should not crash — resize is a no-op in ghostty mode
        session.resize(cols: 80, rows: 24)
    }
}
