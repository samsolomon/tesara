import XCTest
@testable import Tesara

final class OSC133ParserTests: XCTestCase {
    // MARK: Existing Tests

    func testParserExtractsTextAndEventsAcrossChunks() {
        let parser = OSC133Parser()

        let firstPass = parser.feed("\u{1B}]133;B\u{7}git status")
        XCTAssertEqual(firstPass, [.event(.commandInputStart), .text("git status")])

        let secondPass = parser.feed("\n\u{1B}]133;C\u{7}output")
        XCTAssertEqual(secondPass, [.text("\n"), .event(.commandExecuted), .text("output")])
    }

    func testParserKeepsIncompleteSequenceUntilTerminatorArrives() {
        let parser = OSC133Parser()

        XCTAssertEqual(parser.feed("\u{1B}]133;D;0"), [])
        XCTAssertEqual(parser.feed("\u{7}"), [.event(.commandFinished(exitCode: 0))])
    }

    // MARK: BEL vs ST Terminators

    func testBELTerminator() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;A\u{07}")
        XCTAssertEqual(tokens, [.event(.promptStart)])
    }

    func testSTTerminator() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;A\u{1B}\\")
        XCTAssertEqual(tokens, [.event(.promptStart)])
    }

    func testBELAndSTProduceSameEvents() {
        let parserBEL = OSC133Parser()
        let parserST = OSC133Parser()

        let bel = parserBEL.feed("\u{1B}]133;B\u{07}")
        let st = parserST.feed("\u{1B}]133;B\u{1B}\\")

        XCTAssertEqual(bel, st)
    }

    // MARK: Rapid A/B/C/D Sequences

    func testRapidABCDSequence() {
        let parser = OSC133Parser()
        let tokens = parser.feed(
            "\u{1B}]133;A\u{07}" +
            "\u{1B}]133;B\u{07}" +
            "ls" +
            "\u{1B}]133;C\u{07}" +
            "file1 file2" +
            "\u{1B}]133;D;0\u{07}"
        )
        XCTAssertEqual(tokens, [
            .event(.promptStart),
            .event(.commandInputStart),
            .text("ls"),
            .event(.commandExecuted),
            .text("file1 file2"),
            .event(.commandFinished(exitCode: 0))
        ])
    }

    func testConsecutiveEventsWithNoText() {
        let parser = OSC133Parser()
        let tokens = parser.feed(
            "\u{1B}]133;A\u{07}" +
            "\u{1B}]133;B\u{07}" +
            "\u{1B}]133;C\u{07}" +
            "\u{1B}]133;D\u{07}"
        )
        XCTAssertEqual(tokens, [
            .event(.promptStart),
            .event(.commandInputStart),
            .event(.commandExecuted),
            .event(.commandFinished(exitCode: nil))
        ])
    }

    // MARK: Malformed / Unknown Sequences

    func testNonOSC133SequenceIsDropped() {
        let parser = OSC133Parser()
        // OSC 7 (cwd reporting) — not 133, should be silently dropped
        let tokens = parser.feed("\u{1B}]7;file:///Users/test\u{07}hello")
        XCTAssertEqual(tokens, [.text("hello")])
    }

    func testUnknownOSC133SubcommandIsDropped() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;Z\u{07}text")
        XCTAssertEqual(tokens, [.text("text")])
    }

    // MARK: Empty Text Between Events

    func testEmptyTextNotEmitted() {
        let parser = OSC133Parser()
        // Two events back-to-back — no text token should appear between them
        let tokens = parser.feed("\u{1B}]133;A\u{07}\u{1B}]133;B\u{07}")
        XCTAssertEqual(tokens, [.event(.promptStart), .event(.commandInputStart)])
    }

    // MARK: Interleaved Text and Events

    func testInterleavedTextAndEvents() {
        let parser = OSC133Parser()
        let tokens = parser.feed("prompt$ \u{1B}]133;B\u{07}echo hi\u{1B}]133;C\u{07}hi\n\u{1B}]133;D;0\u{07}")
        XCTAssertEqual(tokens, [
            .text("prompt$ "),
            .event(.commandInputStart),
            .text("echo hi"),
            .event(.commandExecuted),
            .text("hi\n"),
            .event(.commandFinished(exitCode: 0))
        ])
    }

    // MARK: Exit Code Parsing

    func testExitCodeZero() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;D;0\u{07}")
        XCTAssertEqual(tokens, [.event(.commandFinished(exitCode: 0))])
    }

    func testExitCodeNonZero() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;D;127\u{07}")
        XCTAssertEqual(tokens, [.event(.commandFinished(exitCode: 127))])
    }

    func testExitCodeMissing() {
        let parser = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;D\u{07}")
        XCTAssertEqual(tokens, [.event(.commandFinished(exitCode: nil))])
    }

    // MARK: Reset

    func testResetClearsPendingState() {
        let parser = OSC133Parser()
        // Feed incomplete sequence
        _ = parser.feed("\u{1B}]133;B")
        parser.reset()
        // After reset, should not complete the old sequence
        let tokens = parser.feed("\u{07}hello")
        // The BEL should appear as text since there's no pending ESC]
        XCTAssertEqual(tokens, [.text("\u{07}hello")])
    }

    // MARK: Chunked Input

    func testSequenceSplitAcrossTwoChunks() {
        let parser = OSC133Parser()

        // Sequence split at ESC] boundary — parser buffers from ESC] onward
        XCTAssertEqual(parser.feed("\u{1B}]133;A"), [])
        XCTAssertEqual(parser.feed("\u{07}"), [.event(.promptStart)])
    }

    func testSequenceSplitAtContentBoundary() {
        let parser = OSC133Parser()

        XCTAssertEqual(parser.feed("text\u{1B}]133;D;12"), [.text("text")])
        XCTAssertEqual(parser.feed("7\u{07}more"), [.event(.commandFinished(exitCode: 127)), .text("more")])
    }

    func testPlainTextWithNoSequences() {
        let parser = OSC133Parser()
        let tokens = parser.feed("just plain text\nwith newlines\n")
        XCTAssertEqual(tokens, [.text("just plain text\nwith newlines\n")])
    }

    // MARK: Protocol Conformance

    func testConformsToOSC133ParsingProtocol() {
        let parser: OSC133Parsing = OSC133Parser()
        let tokens = parser.feed("\u{1B}]133;A\u{07}")
        XCTAssertEqual(tokens, [.event(.promptStart)])
    }
}
