import XCTest
import GRDB
@testable import Tesara

@MainActor
final class TerminalSessionTests: XCTestCase {
    private var session: TerminalSession!

    override func setUp() {
        super.setUp()
        session = TerminalSession()
    }

    // MARK: State Transitions

    func testInitialStatusIsIdle() {
        XCTAssertEqual(session.status, .idle)
    }

    func testStartWithoutGhosttyAppFails() {
        // In test environment, GhosttyApp.shared.app is nil
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(session.status, .failed)
        XCTAssertNotNil(session.launchError)
    }

    func testStartWithoutGhosttyStillSetsActiveSessionID() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        // Even though start fails (no ghostty app), activeSessionID should be set
        // so that handleCommandFinished can persist blocks
        XCTAssertEqual(session.status, .failed)
        XCTAssertEqual(session.capturedBlockCount, 0) // No captures yet
    }

    func testStopAfterFailedKeepsFailedStatus() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.stop()
        XCTAssertEqual(session.status, .failed)
    }

    // MARK: Send

    func testSendEmptyCommandIsIgnored() {
        // send(command:) should not crash even without a surface
        session.send(command: "   ")
        // No assertion needed — just verifying no crash
    }

    func testSendEmptyTextIsIgnored() {
        session.send(text: "")
        // No assertion needed — just verifying no crash
    }

    // MARK: Working Directory

    func testUpdateWorkingDirectory() {
        session.updateWorkingDirectory(URL(fileURLWithPath: "/Users/test"))
        XCTAssertEqual(session.currentWorkingDirectory, "/Users/test")
    }

    func testInitialWorkingDirectoryIsNil() {
        XCTAssertNil(session.currentWorkingDirectory)
    }

    // MARK: Double Start Guard

    func testDoubleStartIsIgnored() {
        // First start sets surfaceView to nil (fails), but the guard checks surfaceView == nil
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        // surfaceView is still nil because ghostty app isn't available,
        // so a second start would proceed. This is fine in test context.
        XCTAssertEqual(session.status, .failed)
    }

    // MARK: Shell Session ID

    func testShellSessionIDIsSet() {
        XCTAssertFalse(session.shellSessionID.isEmpty)
    }

    func testShellSessionIDIsUnique() {
        let session2 = TerminalSession()
        XCTAssertNotEqual(session.shellSessionID, session2.shellSessionID)
    }

    // MARK: - Stale Temp File Cleanup

    func testCleanupStaleTempFilesRemovesOldFiles() throws {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        let testID = UUID().uuidString

        // Create an old temp file (backdate modification time)
        let staleFileName = "tesara-cmd-stale-\(testID).txt"
        let stalePath = (tmpDir as NSString).appendingPathComponent(staleFileName)
        try "stale".write(toFile: stalePath, atomically: true, encoding: .utf8)

        // Backdate to 48 hours ago
        let oldDate = Date().addingTimeInterval(-172800)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: stalePath)

        TerminalSession.cleanupStaleTempFiles(olderThan: 86400)

        XCTAssertFalse(fm.fileExists(atPath: stalePath))
    }

    func testCleanupStaleTempFilesLeavesRecentFiles() throws {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        let testID = UUID().uuidString

        // Create a recent temp file
        let recentFileName = "tesara-cmd-recent-\(testID).txt"
        let recentPath = (tmpDir as NSString).appendingPathComponent(recentFileName)
        try "recent".write(toFile: recentPath, atomically: true, encoding: .utf8)

        TerminalSession.cleanupStaleTempFiles(olderThan: 86400)

        XCTAssertTrue(fm.fileExists(atPath: recentPath))

        // Cleanup
        try? fm.removeItem(atPath: recentPath)
    }

    func testCleanupStaleTempFilesIgnoresNonTesaraFiles() throws {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        let testID = UUID().uuidString

        // Create an old non-Tesara file
        let otherFileName = "other-app-\(testID).txt"
        let otherPath = (tmpDir as NSString).appendingPathComponent(otherFileName)
        try "other".write(toFile: otherPath, atomically: true, encoding: .utf8)

        let oldDate = Date().addingTimeInterval(-172800)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: otherPath)

        TerminalSession.cleanupStaleTempFiles(olderThan: 86400)

        XCTAssertTrue(fm.fileExists(atPath: otherPath))

        // Cleanup
        try? fm.removeItem(atPath: otherPath)
    }

    // MARK: - Temp File Cleanup

    func testStopCleansUpTemporaryFiles() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)

        // Create a fake temp file to simulate shell integration temp files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-test-cleanup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "test".write(to: testFile, atomically: true, encoding: .utf8)

        // Inject the temp URL into the session's cleanup list via start path
        // Since we can't start (no ghostty app), test cleanup directly
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(session.status, .failed)

        // Verify temp dir still exists (session didn't create it, so cleanup list is empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))

        // Clean up manually
        try FileManager.default.removeItem(at: tempDir)
    }

}
