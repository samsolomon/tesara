import XCTest
@testable import Tesara

final class TerminalBlockCaptureTests: XCTestCase {
    func testInitialStageIsCommand() {
        let capture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .command)
        XCTAssertEqual(capture.stage, .command)
        XCTAssertTrue(capture.commandText.isEmpty)
        XCTAssertTrue(capture.outputText.isEmpty)
        XCTAssertNil(capture.exitCode)
    }

    func testCommandStageAccumulatesText() {
        var capture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .command)
        capture.commandText.append("ls ")
        capture.commandText.append("-la")
        XCTAssertEqual(capture.commandText, "ls -la")
    }

    func testTransitionToOutputStage() {
        var capture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .command)
        capture.commandText = "echo hello"
        capture.stage = .output
        XCTAssertEqual(capture.stage, .output)
        XCTAssertEqual(capture.commandText, "echo hello")
    }

    func testOutputStageAccumulatesText() {
        var capture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .output)
        capture.outputText.append("line 1\n")
        capture.outputText.append("line 2\n")
        XCTAssertEqual(capture.outputText, "line 1\nline 2\n")
    }

    func testExitCodeAssignment() {
        var capture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .output)
        capture.exitCode = 0
        XCTAssertEqual(capture.exitCode, 0)

        capture.exitCode = 127
        XCTAssertEqual(capture.exitCode, 127)
    }

    func testFinishedAtUpdate() {
        let start = Date()
        var capture = TerminalBlockCapture(startedAt: start, finishedAt: start, stage: .command)
        let later = Date(timeIntervalSince1970: start.timeIntervalSince1970 + 5)
        capture.finishedAt = later
        XCTAssertEqual(capture.finishedAt, later)
        XCTAssertEqual(capture.startedAt, start)
    }
}
