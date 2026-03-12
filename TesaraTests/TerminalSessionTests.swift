import XCTest
import GRDB
@testable import Tesara

// MARK: - Mock Launcher & Process Handle

private final class MockProcessHandle: TerminalProcessHandle {
    var sentTexts: [String] = []
    var lastResize: (cols: UInt16, rows: UInt16)?
    var stopped = false

    func send(_ input: String) throws {
        sentTexts.append(input)
    }

    func resize(cols: UInt16, rows: UInt16) {
        lastResize = (cols, rows)
    }

    func stop() {
        stopped = true
    }
}

private final class MockLauncher: TerminalLaunching {
    var shouldFail = false
    var onEventCallback: ((TerminalEvent) -> Void)?
    var mockHandle: MockProcessHandle?

    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle {
        if shouldFail {
            throw TerminalLaunchError.invalidShellPath
        }

        onEventCallback = onEvent
        let handle = MockProcessHandle()
        mockHandle = handle
        return handle
    }

    func simulateStdout(_ text: String) {
        onEventCallback?(.stdout(text))
    }

    func simulateExit(_ code: Int32) {
        onEventCallback?(.exit(code))
    }
}

// MARK: - Tests

@MainActor
final class TerminalSessionTests: XCTestCase {
    private var launcher: MockLauncher!
    private var session: TerminalSession!

    override func setUp() {
        super.setUp()
        launcher = MockLauncher()
        session = TerminalSession(launcher: launcher)
    }

    // MARK: State Transitions

    func testInitialStatusIsIdle() {
        XCTAssertEqual(session.status, .idle)
    }

    func testSuccessfulLaunchTransitionsToRunning() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(session.status, .running)
    }

    func testFailedLaunchTransitionsToFailed() {
        launcher.shouldFail = true
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(session.status, .failed)
        XCTAssertNotNil(session.launchError)
    }

    func testStopTransitionsToStopped() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.stop()
        XCTAssertEqual(session.status, .stopped)
    }

    func testStopAfterFailedKeepsFailedStatus() {
        launcher.shouldFail = true
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.stop()
        XCTAssertEqual(session.status, .failed)
    }

    // MARK: Resize

    func testResizeWithPositiveValues() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.resize(cols: 80, rows: 24)
        XCTAssertEqual(launcher.mockHandle?.lastResize?.cols, 80)
        XCTAssertEqual(launcher.mockHandle?.lastResize?.rows, 24)
    }

    func testResizeWithZeroIsIgnored() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.resize(cols: 0, rows: 24)
        XCTAssertNil(launcher.mockHandle?.lastResize)
    }

    func testResizeWithNegativeIsIgnored() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.resize(cols: -1, rows: 24)
        XCTAssertNil(launcher.mockHandle?.lastResize)
    }

    // MARK: Send

    func testSendCommandTrimsAndAppendsNewline() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.send(command: "  ls -la  ")
        XCTAssertEqual(launcher.mockHandle?.sentTexts, ["ls -la\n"])
    }

    func testSendEmptyCommandIsIgnored() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.send(command: "   ")
        XCTAssertEqual(launcher.mockHandle?.sentTexts, [])
    }

    func testSendTextPassesDirectly() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.send(text: "raw input")
        XCTAssertEqual(launcher.mockHandle?.sentTexts, ["raw input"])
    }

    func testSendEmptyTextIsIgnored() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.send(text: "")
        XCTAssertEqual(launcher.mockHandle?.sentTexts, [])
    }

    // MARK: Block Capture

    func testBlockCaptureLifecycle() async throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        // OSC 133 B → command input start
        launcher.simulateStdout("\u{1B}]133;B\u{07}")
        await yieldToMainActor()

        // Type command text
        launcher.simulateStdout("echo hello")
        await yieldToMainActor()

        // OSC 133 C → command executed
        launcher.simulateStdout("\u{1B}]133;C\u{07}")
        await yieldToMainActor()

        // Output text
        launcher.simulateStdout("hello\n")
        await yieldToMainActor()

        // OSC 133 D → command finished
        launcher.simulateStdout("\u{1B}]133;D;0\u{07}")
        await yieldToMainActor()

        XCTAssertEqual(session.capturedBlockCount, 1)
    }

    func testEmptyCommandSkipsCapture() async throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        // B → C → D with no text between B and C (empty command)
        launcher.simulateStdout("\u{1B}]133;B\u{07}")
        await yieldToMainActor()
        launcher.simulateStdout("\u{1B}]133;C\u{07}")
        await yieldToMainActor()
        launcher.simulateStdout("\u{1B}]133;D;0\u{07}")
        await yieldToMainActor()

        XCTAssertEqual(session.capturedBlockCount, 0)
    }

    func testCapturedBlockCountIncrementsWithMultipleBlocks() async throws {
        let blockStore = try BlockStore(dbQueue: DatabaseQueue())
        session.configure(blockStore: blockStore)
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        for i in 0..<3 {
            launcher.simulateStdout("\u{1B}]133;B\u{07}cmd\(i)\u{1B}]133;C\u{07}out\(i)\u{1B}]133;D;0\u{07}")
            await yieldToMainActor()
        }

        XCTAssertEqual(session.capturedBlockCount, 3)
    }

    // MARK: Transcript

    func testTranscriptAccumulatesOutput() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        launcher.simulateStdout("hello ")
        await yieldToMainActor()
        launcher.simulateStdout("world")
        await yieldToMainActor()

        let fullText = session.transcriptLog.contentSince(offset: 0)
        XCTAssertTrue(fullText.contains("hello "))
        XCTAssertTrue(fullText.contains("world"))
    }

    // MARK: OSC 7 CWD Tracking

    func testOSC7UpdatesCurrentWorkingDirectory() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        launcher.simulateStdout("\u{1B}]7;file://localhost/Users/sam/projects\u{07}")
        await yieldToMainActor()

        XCTAssertEqual(session.currentWorkingDirectory, "/Users/sam/projects")
    }

    func testOSC7WithSTTerminator() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        launcher.simulateStdout("\u{1B}]7;file://localhost/tmp\u{1B}\\")
        await yieldToMainActor()

        XCTAssertEqual(session.currentWorkingDirectory, "/tmp")
    }

    func testOSC7IgnoresNonFileSchemes() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        launcher.simulateStdout("\u{1B}]7;http://example.com/path\u{07}")
        await yieldToMainActor()

        XCTAssertNil(session.currentWorkingDirectory)
    }

    func testOSC7WithPercentEncodedPath() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        launcher.simulateStdout("\u{1B}]7;file://localhost/Users/sam/my%20project\u{07}")
        await yieldToMainActor()

        XCTAssertEqual(session.currentWorkingDirectory, "/Users/sam/my project")
    }

    func testOSC7InitiallyNil() {
        XCTAssertNil(session.currentWorkingDirectory)
    }

    // MARK: TUI Passthrough

    func testTUIPassthroughSkipsParser() async {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        session.tuiPassthroughEnabled = true

        // Send raw OSC 133 — should NOT trigger block capture
        launcher.simulateStdout("\u{1B}]133;B\u{07}echo hi\u{1B}]133;C\u{07}hi\u{1B}]133;D;0\u{07}")
        await yieldToMainActor()

        XCTAssertEqual(session.capturedBlockCount, 0)

        // But transcript should still contain the raw text
        let content = session.transcriptLog.contentSince(offset: 0)
        XCTAssertTrue(content.contains("echo hi"))
    }

    // MARK: Guard against double start

    func testDoubleStartIsIgnored() {
        session.start(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let firstHandle = launcher.mockHandle
        session.start(shellPath: "/bin/bash", workingDirectory: URL(fileURLWithPath: "/tmp"))
        // Should still be the first handle (second start was ignored)
        XCTAssertTrue(launcher.mockHandle === firstHandle)
    }

    // MARK: Helpers

    private func yieldToMainActor() async {
        // Allow Task { @MainActor } blocks from onEvent to execute
        await Task.yield()
        await Task.yield()
    }
}
