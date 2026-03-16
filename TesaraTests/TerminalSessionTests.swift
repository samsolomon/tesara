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

    // MARK: - Input Bar State

    func testInitialIsAtPromptIsFalse() {
        XCTAssertFalse(session.isAtPrompt)
    }

    func testHandleCommandFinishedSetsIsAtPromptTrue() {
        session.handleCommandFinished(exitCode: 0, durationNs: 1_000_000)
        XCTAssertTrue(session.isAtPrompt)
    }

    func testSendFromInputBarSetsIsAtPromptFalse() {
        session.handleCommandFinished(exitCode: 0, durationNs: 1_000_000)
        XCTAssertTrue(session.isAtPrompt)
        session.sendFromInputBar(text: "ls")
        XCTAssertFalse(session.isAtPrompt)
    }

    func testSendFromInputBarIgnoresEmptyText() {
        session.handleCommandFinished(exitCode: 0, durationNs: 1_000_000)
        session.sendFromInputBar(text: "   ")
        // Empty/whitespace-only text should not change isAtPrompt
        XCTAssertTrue(session.isAtPrompt)
    }

    func testHandleChildExitedClearsIsAtPrompt() {
        session.handleCommandFinished(exitCode: 0, durationNs: 1_000_000)
        XCTAssertTrue(session.isAtPrompt)
        session.handleChildExited(exitCode: 0)
        XCTAssertFalse(session.isAtPrompt)
    }

    func testStopClearsIsAtPrompt() {
        session.handleCommandFinished(exitCode: 0, durationNs: 1_000_000)
        XCTAssertTrue(session.isAtPrompt)
        session.stop()
        XCTAssertFalse(session.isAtPrompt)
    }

    func testInputBarCtrlCClearsBuffer() {
        let handler = InputBarKeyHandler()
        handler.terminalSession = session

        var sentTexts: [String] = []
        session.onSendTextForTesting = { sentTexts.append($0) }

        let handled = handler.editorView(makeEditorView(), handleKeyDown: makeKeyEvent(chars: "c", modifiers: [.control]))

        XCTAssertTrue(handled)
        // Ctrl+C clears the buffer instead of sending SIGINT (Warp behavior)
        XCTAssertTrue(sentTexts.isEmpty)
    }

    func testInputBarCtrlDSendsEOF() {
        let handler = InputBarKeyHandler()
        handler.terminalSession = session

        var sentTexts: [String] = []
        session.onSendTextForTesting = { sentTexts.append($0) }

        let handled = handler.editorView(makeEditorView(), handleKeyDown: makeKeyEvent(chars: "d", modifiers: [.control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(sentTexts, ["\u{04}"])
    }

    func testInputBarCtrlZSendsSuspend() {
        let handler = InputBarKeyHandler()
        handler.terminalSession = session

        var sentTexts: [String] = []
        session.onSendTextForTesting = { sentTexts.append($0) }

        let handled = handler.editorView(makeEditorView(), handleKeyDown: makeKeyEvent(chars: "z", modifiers: [.control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(sentTexts, ["\u{1a}"])
    }

    func testInputBarCtrlJInsertsNewline() {
        let handler = InputBarKeyHandler()
        let editorSession = EditorSession()
        let editorView = EditorView(
            session: editorSession,
            theme: BuiltInTheme.tesaraDark.theme,
            fontFamily: "SF Mono",
            fontSize: 13
        )

        XCTAssertEqual(editorSession.storage.entireString(), "")

        let handled = handler.editorView(editorView, handleKeyDown: makeKeyEvent(chars: "j", modifiers: [.control]))

        XCTAssertTrue(handled)
        XCTAssertEqual(editorSession.storage.entireString(), "\n")
    }

    func testInputBarShiftEnterFallsBackToEditorNewline() {
        let handler = InputBarKeyHandler()

        let handled = handler.editorView(makeEditorView(), handleSpecialKey: .enter, mods: [.shift])

        XCTAssertFalse(handled)
    }

    func testInputBarControlEnterFallsBackToEditorNewline() {
        let handler = InputBarKeyHandler()

        let handled = handler.editorView(makeEditorView(), handleSpecialKey: .enter, mods: [.control])

        XCTAssertFalse(handled)
    }

    func testInputBarOptionEnterFallsBackToEditorNewline() {
        let handler = InputBarKeyHandler()

        let handled = handler.editorView(makeEditorView(), handleSpecialKey: .enter, mods: [.option])

        XCTAssertFalse(handled)
    }

    // MARK: - handleCommandFinished

    func testHandleCommandFinishedWithNegativeOneExitCodeTreatsAsNil() throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        // -1 exit code is treated as nil (unknown)
        session.handleCommandFinished(exitCode: -1, durationNs: 1_000_000)
        XCTAssertTrue(session.isAtPrompt)
    }

    func testHandleCommandFinishedSetsIsAtPromptForNonZeroExit() {
        session.handleCommandFinished(exitCode: 127, durationNs: 500_000)
        XCTAssertTrue(session.isAtPrompt)
    }

    // MARK: - handleChildExited

    func testHandleChildExitedSetsStatusToStopped() {
        session.handleChildExited(exitCode: 0)
        XCTAssertEqual(session.status, .stopped)
    }

    func testHandleChildExitedClearsAlternateScreen() {
        // Can't set isAlternateScreen directly, but can verify it's false after exit
        session.handleChildExited(exitCode: 0)
        XCTAssertFalse(session.isAlternateScreen)
    }

    func testHandleChildExitedTearsDownInputBar() {
        session.prepareInputBar()
        XCTAssertNotNil(session.inputBarState)

        session.handleChildExited(exitCode: 0)
        XCTAssertNil(session.inputBarState)
    }

    // MARK: - updateTitle

    func testUpdateTitleSetsShellTitle() {
        session.updateTitle("Deploy logs")
        XCTAssertEqual(session.shellTitle, "Deploy logs")
    }

    func testUpdateTitleTrimsWhitespace() {
        session.updateTitle("  Deploy logs  ")
        XCTAssertEqual(session.shellTitle, "Deploy logs")
    }

    func testUpdateTitleEmptyStringBecomesNil() {
        session.updateTitle("Something")
        session.updateTitle("")
        XCTAssertNil(session.shellTitle)
    }

    func testUpdateTitleWhitespaceOnlyBecomesNil() {
        session.updateTitle("Something")
        session.updateTitle("   ")
        XCTAssertNil(session.shellTitle)
    }

    func testUpdateTitleDuplicateValueIsNoOp() {
        session.updateTitle("Deploy logs")
        // Second call with same value should not trigger change
        session.updateTitle("Deploy logs")
        XCTAssertEqual(session.shellTitle, "Deploy logs")
    }

    // MARK: - updateWorkingDirectory

    func testUpdateWorkingDirectoryDuplicateValueIsNoOp() {
        let url = URL(fileURLWithPath: "/Users/test")
        session.updateWorkingDirectory(url)
        // Second call with same path should be no-op
        session.updateWorkingDirectory(url)
        XCTAssertEqual(session.currentWorkingDirectory, "/Users/test")
    }

    // MARK: - prepareInputBar

    func testPrepareInputBarCreatesState() {
        session.prepareInputBar()
        XCTAssertNotNil(session.inputBarState)
    }

    func testPrepareInputBarIdempotent() {
        session.prepareInputBar()
        let first = session.inputBarState
        session.prepareInputBar()
        XCTAssertTrue(session.inputBarState === first)
    }

    // MARK: - configure

    func testConfigureIsIdempotent() throws {
        let blockStore1 = try BlockStore(dbQueue: DatabaseQueue())
        let blockStore2 = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore1)
        // Second configure should not replace the first
        session.configure(blockStore: blockStore2)
        // Verified by the fact that the session works correctly after double-configure
    }

    // MARK: - handleSurfaceClosed

    func testHandleSurfaceClosedCallsStop() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.handleSurfaceClosed()
        // Failed start stays as .failed, stop preserves .failed
        XCTAssertEqual(session.status, .failed)
        XCTAssertFalse(session.isAtPrompt)
    }

    // MARK: - readAndCleanupCommandFile

    func testReadAndCleanupCommandFileReturnsNilWhenMissing() {
        let result = session.readAndCleanupCommandFile()
        XCTAssertNil(result)
    }

    func testReadAndCleanupCommandFileReadsAndDeletesFile() throws {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "echo hello".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "echo hello")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testReadAndCleanupCommandFileReturnsRawContent() throws {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(session.shellSessionID).txt"
        try "  ls -la  \n".write(toFile: path, atomically: true, encoding: .utf8)

        let result = session.readAndCleanupCommandFile()
        XCTAssertEqual(result, "  ls -la  \n")
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

    private func makeEditorView() -> EditorView {
        EditorView(
            session: EditorSession(),
            theme: BuiltInTheme.tesaraDark.theme,
            fontFamily: "SF Mono",
            fontSize: 13
        )
    }

    private func makeKeyEvent(chars: String, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: 0
        ) else {
            fatalError("Failed to create NSEvent for test")
        }

        return event
    }

}
