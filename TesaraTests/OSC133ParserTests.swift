import XCTest
@testable import Tesara

final class OSC133ParserTests: XCTestCase {
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
}
