import XCTest
@testable import Tesara

final class JSONTokenizerTests: XCTestCase {

    private let tokenizer = JSONTokenizer()

    private func extractText(_ line: String, token: SyntaxToken) -> String {
        let utf16 = Array(line.utf16)
        let slice = Array(utf16[token.range])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    private func tokenize(_ line: String) -> [SyntaxToken] {
        var state = TokenizerState()
        return tokenizer.tokenize(line: line, state: &state)
    }

    // MARK: - Keys vs Values

    func testKeyIsKeyword() {
        let tokens = tokenize(#"  "name": "value""#)
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.count, 1)
    }

    func testValueIsString() {
        let tokens = tokenize(#"  "name": "value""#)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    func testStringWithNoColonIsValue() {
        let tokens = tokenize(#"  "just a value""#)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    func testKeyWithSpacesBeforeColon() {
        let tokens = tokenize(#"  "key"  : "val""#)
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.count, 1)
    }

    // MARK: - Strings

    func testStringWithEscapedQuote() {
        let tokens = tokenize(#""he said \"hi\"""#)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    func testEmptyString() {
        let tokens = tokenize(#""""#)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    // MARK: - Numbers

    func testInteger() {
        let tokens = tokenize("42")
        XCTAssertEqual(tokens.filter { $0.kind == .number }.count, 1)
        XCTAssertEqual(extractText("42", token: tokens[0]), "42")
    }

    func testNegativeNumber() {
        let tokens = tokenize("-42")
        XCTAssertEqual(extractText("-42", token: tokens[0]), "-42")
    }

    func testFloat() {
        let tokens = tokenize("3.14")
        XCTAssertEqual(extractText("3.14", token: tokens[0]), "3.14")
    }

    func testScientificNotation() {
        let tokens = tokenize("1.5e10")
        XCTAssertEqual(extractText("1.5e10", token: tokens[0]), "1.5e10")
    }

    func testScientificNotationNegativeExponent() {
        let tokens = tokenize("1.5e-3")
        XCTAssertEqual(extractText("1.5e-3", token: tokens[0]), "1.5e-3")
    }

    // MARK: - Literals

    func testTrue() {
        let lits = tokenize("true").filter { $0.kind == .literal }
        XCTAssertEqual(lits.count, 1)
    }

    func testFalse() {
        let lits = tokenize("false").filter { $0.kind == .literal }
        XCTAssertEqual(lits.count, 1)
    }

    func testNull() {
        let lits = tokenize("null").filter { $0.kind == .literal }
        XCTAssertEqual(lits.count, 1)
    }

    func testLiteralNotPartOfIdentifier() {
        XCTAssertTrue(tokenize("truely").filter { $0.kind == .literal }.isEmpty)
    }

    func testNullNotPartOfIdentifier() {
        XCTAssertTrue(tokenize("nullable").filter { $0.kind == .literal }.isEmpty)
    }

    // MARK: - Full JSON Lines

    func testComplexJSONLine() {
        let tokens = tokenize(#"  "count": 42, "active": true, "data": null"#)
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.count, 3)
        XCTAssertEqual(tokens.filter { $0.kind == .number }.count, 1)
        XCTAssertEqual(tokens.filter { $0.kind == .literal }.count, 2)
    }

    func testArrayLine() {
        let tokens = tokenize(#"  [1, 2, "three", true, null]"#)
        XCTAssertEqual(tokens.filter { $0.kind == .number }.count, 2)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
        XCTAssertEqual(tokens.filter { $0.kind == .literal }.count, 2)
    }

    // MARK: - Edge Cases

    func testEmptyLine() {
        XCTAssertTrue(tokenize("").isEmpty)
    }

    func testWhitespaceOnly() {
        XCTAssertTrue(tokenize("   \t  ").isEmpty)
    }

    func testTokenRangesDoNotOverlap() {
        let tokens = tokenize(#"  "key": "value", "num": -3.14e2, "flag": true"#)
        for i in 1..<tokens.count {
            XCTAssertGreaterThanOrEqual(tokens[i].range.lowerBound, tokens[i - 1].range.upperBound)
        }
    }
}
