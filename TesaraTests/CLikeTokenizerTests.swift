import XCTest
@testable import Tesara

final class CLikeTokenizerTests: XCTestCase {

    private func extractText(_ line: String, token: SyntaxToken) -> String {
        let utf16 = Array(line.utf16)
        let slice = Array(utf16[token.range])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    private func tokenize(_ line: String, config: LanguageConfig = .swift, state: inout TokenizerState) -> [SyntaxToken] {
        CLikeTokenizer(config: config).tokenize(line: line, state: &state)
    }

    // MARK: - Block Comments

    func testBlockCommentSingleLine() {
        var state = TokenizerState()
        let tokens = tokenize("/* comment */", state: &state)
        XCTAssertFalse(state.inBlockComment)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testBlockCommentSpansTwoLines() {
        var state = TokenizerState()
        _ = tokenize("code /* start", state: &state)
        XCTAssertTrue(state.inBlockComment)
        let tokens2 = tokenize("end */ more", state: &state)
        XCTAssertFalse(state.inBlockComment)
        XCTAssertFalse(tokens2.filter { $0.kind == .comment }.isEmpty)
    }

    func testBlockCommentEntireLineIsContinuation() {
        var state = TokenizerState()
        _ = tokenize("/*", state: &state)
        let tokens = tokenize("all comment text here", state: &state)
        XCTAssertTrue(state.inBlockComment)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testBlockCommentFollowedByCode() {
        var state = TokenizerState()
        _ = tokenize("/*", state: &state)
        let tokens = tokenize("*/ let x = 5", state: &state)
        XCTAssertFalse(state.inBlockComment)
        XCTAssertFalse(tokens.filter { $0.kind == .keyword }.isEmpty)
    }

    // MARK: - Strings

    func testSingleQuotedString() {
        var state = TokenizerState()
        let tokens = tokenize("let x = 'hello'", state: &state)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
    }

    func testBacktickTemplateLiteral() {
        var state = TokenizerState()
        let line = "let x = `template string`"
        let tokens = tokenize(line, config: .javascript, state: &state)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(extractText(line, token: strings[0]), "`template string`")
    }

    func testStringWithEscapedQuote() {
        var state = TokenizerState()
        let line = #"let x = "he said \"hi\"""#
        let tokens = tokenize(line, state: &state)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    func testEmptyString() {
        var state = TokenizerState()
        let line = #"let x = """#
        let tokens = tokenize(line, state: &state)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
    }

    // MARK: - Numbers

    func testHexNumber() {
        var state = TokenizerState()
        let line = "let x = 0xFF"
        let tokens = tokenize(line, state: &state)
        let nums = tokens.filter { $0.kind == .number }
        XCTAssertEqual(nums.count, 1)
        XCTAssertEqual(extractText(line, token: nums[0]), "0xFF")
    }

    func testBinaryNumber() {
        var state = TokenizerState()
        let line = "let x = 0b1010"
        let nums = tokenize(line, state: &state).filter { $0.kind == .number }
        XCTAssertEqual(nums.count, 1)
        XCTAssertEqual(extractText(line, token: nums[0]), "0b1010")
    }

    func testOctalNumber() {
        var state = TokenizerState()
        let line = "let x = 0o77"
        let nums = tokenize(line, state: &state).filter { $0.kind == .number }
        XCTAssertEqual(extractText(line, token: nums[0]), "0o77")
    }

    func testFloatWithExponent() {
        var state = TokenizerState()
        let line = "let x = 1.5e10"
        let nums = tokenize(line, state: &state).filter { $0.kind == .number }
        XCTAssertEqual(extractText(line, token: nums[0]), "1.5e10")
    }

    func testNumberWithUnderscores() {
        var state = TokenizerState()
        let line = "let x = 1_000_000"
        let nums = tokenize(line, state: &state).filter { $0.kind == .number }
        XCTAssertEqual(extractText(line, token: nums[0]), "1_000_000")
    }

    // MARK: - Preprocessor

    func testCPreprocessorDirective() {
        var state = TokenizerState()
        let line = "#include <stdio.h>"
        let kws = tokenize(line, config: .c, state: &state).filter { $0.kind == .keyword }
        XCTAssertTrue(kws.contains(where: { extractText(line, token: $0) == "#include" }))
    }

    func testNonPreprocessorHashIsPlain() {
        var state = TokenizerState()
        let tokens = tokenize("#something", config: .swift, state: &state)
        XCTAssertTrue(tokens.filter { $0.kind == .keyword }.isEmpty)
    }

    // MARK: - Operators

    func testMultiCharOperator() {
        var state = TokenizerState()
        let line = "a == b"
        let ops = tokenize(line, state: &state).filter { $0.kind == .operator }
        XCTAssertTrue(ops.contains(where: { extractText(line, token: $0) == "==" }))
    }

    func testBracketsAreSeparateOperators() {
        var state = TokenizerState()
        let ops = tokenize("foo()", state: &state).filter { $0.kind == .operator }
        XCTAssertTrue(ops.count >= 2)
    }

    // MARK: - Identifiers & Language Configs

    func testIdentifierClassifiedAsPlain() {
        var state = TokenizerState()
        let tokens = tokenize("myVariable", state: &state)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .plain)
    }

    func testGoKeywords() {
        var state = TokenizerState()
        let line = "func main() {"
        let kws = tokenize(line, config: .go, state: &state).filter { $0.kind == .keyword }
        XCTAssertTrue(kws.contains(where: { extractText(line, token: $0) == "func" }))
    }

    func testRustKeywords() {
        var state = TokenizerState()
        let line = "fn main() {"
        let kws = tokenize(line, config: .rust, state: &state).filter { $0.kind == .keyword }
        XCTAssertTrue(kws.contains(where: { extractText(line, token: $0) == "fn" }))
    }

    func testTypescriptExtraKeywords() {
        var state = TokenizerState()
        let line = "interface Foo {"
        let kws = tokenize(line, config: .typescript, state: &state).filter { $0.kind == .keyword }
        XCTAssertTrue(kws.contains(where: { extractText(line, token: $0) == "interface" }))
    }

    func testSwiftLiterals() {
        var state = TokenizerState()
        let lits = tokenize("let x = nil", state: &state).filter { $0.kind == .literal }
        XCTAssertEqual(lits.count, 1)
    }

    func testRustLiterals() {
        var state = TokenizerState()
        let line = "let x = None"
        let lits = tokenize(line, config: .rust, state: &state).filter { $0.kind == .literal }
        XCTAssertTrue(lits.contains(where: { extractText(line, token: $0) == "None" }))
    }

    // MARK: - Edge Cases

    func testEmptyLine() {
        var state = TokenizerState()
        XCTAssertTrue(tokenize("", state: &state).isEmpty)
    }

    func testWhitespaceOnly() {
        var state = TokenizerState()
        XCTAssertTrue(tokenize("   \t  ", state: &state).isEmpty)
    }

    func testLineCommentConsumesRemainder() {
        var state = TokenizerState()
        let line = "// entire line is a comment"
        let tokens = tokenize(line, state: &state)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].kind, .comment)
    }

    func testTokenRangesDoNotOverlap() {
        var state = TokenizerState()
        let tokens = tokenize("let x: Int = 42 + y // comment", state: &state)
        for i in 1..<tokens.count {
            XCTAssertGreaterThanOrEqual(tokens[i].range.lowerBound, tokens[i - 1].range.upperBound)
        }
    }

    func testTokenRangesAreSorted() {
        var state = TokenizerState()
        let tokens = tokenize("func hello() { return true }", state: &state)
        for i in 1..<tokens.count {
            XCTAssertGreaterThanOrEqual(tokens[i].range.lowerBound, tokens[i - 1].range.lowerBound)
        }
    }
}
