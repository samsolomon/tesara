import XCTest
@testable import Tesara

final class AnsiSequenceTests: XCTestCase {
    func testPlainTextPassthrough() {
        XCTAssertEqual("hello world".removingAnsiSequences(), "hello world")
    }

    func testEmptyString() {
        XCTAssertEqual("".removingAnsiSequences(), "")
    }

    func testCSIColorCode() {
        XCTAssertEqual("\u{1b}[31mred text\u{1b}[0m".removingAnsiSequences(), "red text")
    }

    func testOSCWithBELTerminator() {
        XCTAssertEqual("\u{1b}]0;window title\u{07}content".removingAnsiSequences(), "content")
    }

    func testOSCWithSTTerminator() {
        XCTAssertEqual("\u{1b}]0;window title\u{1b}\\content".removingAnsiSequences(), "content")
    }

    func testDCSSequence() {
        XCTAssertEqual("\u{1b}Psome data\u{1b}\\visible".removingAnsiSequences(), "visible")
    }

    func testIncompleteCSIAtEnd() {
        XCTAssertEqual("hello\u{1b}[".removingAnsiSequences(), "hello")
    }

    func testIncompleteOSCAtEnd() {
        XCTAssertEqual("hello\u{1b}]unterminated".removingAnsiSequences(), "hello")
    }

    func testLoneESCAtEnd() {
        XCTAssertEqual("hello\u{1b}".removingAnsiSequences(), "hello")
    }

    func testStandaloneBELStripped() {
        XCTAssertEqual("before\u{07}after".removingAnsiSequences(), "beforeafter")
    }

    func testMixedSequences() {
        let input = "\u{1b}[1m\u{1b}[31mBold Red\u{1b}[0m normal \u{1b}]0;title\u{07}end"
        XCTAssertEqual(input.removingAnsiSequences(), "Bold Red normal end")
    }

    func testMultiParameterCSI() {
        XCTAssertEqual("\u{1b}[38;5;196mcolored\u{1b}[0m".removingAnsiSequences(), "colored")
    }
}
