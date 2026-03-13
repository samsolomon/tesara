import XCTest
@testable import Tesara

final class SyntaxHighlighterTests: XCTestCase {

    // MARK: - CLikeTokenizer

    func testSwiftKeywords() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "func hello() {", state: &state)
        let keywords = tokens.filter { $0.kind == .keyword }
        XCTAssertTrue(keywords.contains(where: { extractText("func hello() {", token: $0) == "func" }))
    }

    func testSwiftStrings() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "let x = \"hello world\"", state: &state)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(extractText("let x = \"hello world\"", token: strings[0]), "\"hello world\"")
    }

    func testLineComment() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "let x = 5 // comment", state: &state)
        let comments = tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 1)
        XCTAssertEqual(extractText("let x = 5 // comment", token: comments[0]), "// comment")
    }

    func testBlockComment() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()

        let tokens1 = tokenizer.tokenize(line: "/* start", state: &state)
        XCTAssertTrue(state.inBlockComment)
        XCTAssertEqual(tokens1.count, 1)
        XCTAssertEqual(tokens1[0].kind, .comment)

        let tokens2 = tokenizer.tokenize(line: "middle", state: &state)
        XCTAssertTrue(state.inBlockComment)
        XCTAssertEqual(tokens2[0].kind, .comment)

        let tokens3 = tokenizer.tokenize(line: "end */ code", state: &state)
        XCTAssertFalse(state.inBlockComment)
        // First token should be the comment portion
        let comments = tokens3.filter { $0.kind == .comment }
        XCTAssertFalse(comments.isEmpty)
    }

    func testNumbers() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "let x = 42 + 3.14", state: &state)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertEqual(numbers.count, 2)
    }

    func testLiterals() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "let x = true", state: &state)
        let literals = tokens.filter { $0.kind == .literal }
        XCTAssertEqual(literals.count, 1)
        XCTAssertEqual(extractText("let x = true", token: literals[0]), "true")
    }

    func testTypeKeywords() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "var x: Int", state: &state)
        let types = tokens.filter { $0.kind == .type }
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(extractText("var x: Int", token: types[0]), "Int")
    }

    func testEscapedStringDoesNotBreakOut() {
        let tokenizer = CLikeTokenizer(config: .swift)
        var state = TokenizerState()
        let line = #"let x = "hello \"world\"!""#
        let tokens = tokenizer.tokenize(line: line, state: &state)
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(strings.count, 1)
    }

    // MARK: - JSONTokenizer

    func testJSONKeys() {
        let tokenizer = JSONTokenizer()
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "  \"name\": \"value\"", state: &state)
        let keys = tokens.filter { $0.kind == .keyword }
        let strings = tokens.filter { $0.kind == .string }
        XCTAssertEqual(keys.count, 1, "Key should be classified as keyword")
        XCTAssertEqual(strings.count, 1, "Value should be classified as string")
    }

    func testJSONNumbers() {
        let tokenizer = JSONTokenizer()
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "  \"count\": 42", state: &state)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertEqual(numbers.count, 1)
    }

    func testJSONLiterals() {
        let tokenizer = JSONTokenizer()
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "  \"active\": true, \"data\": null", state: &state)
        let literals = tokens.filter { $0.kind == .literal }
        XCTAssertEqual(literals.count, 2)
    }

    func testJSONNegativeNumber() {
        let tokenizer = JSONTokenizer()
        var state = TokenizerState()
        let tokens = tokenizer.tokenize(line: "  \"value\": -3.14e2", state: &state)
        let numbers = tokens.filter { $0.kind == .number }
        XCTAssertEqual(numbers.count, 1)
    }

    // MARK: - SyntaxHighlighter

    @MainActor
    func testHighlighterRecognizesSwift() {
        let highlighter = SyntaxHighlighter(fileExtension: "swift")
        XCTAssertTrue(highlighter.isActive)
    }

    @MainActor
    func testHighlighterRecognizesJSON() {
        let highlighter = SyntaxHighlighter(fileExtension: "json")
        XCTAssertTrue(highlighter.isActive)
    }

    @MainActor
    func testHighlighterRejectsUnknown() {
        let highlighter = SyntaxHighlighter(fileExtension: "xyz")
        XCTAssertFalse(highlighter.isActive)
    }

    @MainActor
    func testFullTokenize() {
        let highlighter = SyntaxHighlighter(fileExtension: "swift")
        let storage = TextStorage()
        storage.loadString("let x = 42\nfunc foo() {}")
        highlighter.fullTokenize(storage: storage)

        let line0 = highlighter.tokens(forLine: 0)
        XCTAssertNotNil(line0)
        XCTAssertTrue(line0!.contains(where: { $0.kind == .keyword }))

        let line1 = highlighter.tokens(forLine: 1)
        XCTAssertNotNil(line1)
        XCTAssertTrue(line1!.contains(where: { $0.kind == .keyword }))
    }

    // MARK: - SyntaxColorMap

    func testSyntaxColorMapMapsAllKinds() {
        let theme = TerminalTheme(
            id: "test", name: "Test",
            foreground: "#cccccc", background: "#1e1e1e",
            cursor: "#cccccc", cursorText: "#000000",
            selectionBackground: "#3c5a96", selectionForeground: nil,
            black: "#000000", red: "#ff0000", green: "#00ff00",
            yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
            cyan: "#00ffff", white: "#ffffff",
            brightBlack: "#808080", brightRed: "#ff5555", brightGreen: "#55ff55",
            brightYellow: "#ffff55", brightBlue: "#5555ff", brightMagenta: "#ff55ff",
            brightCyan: "#55ffff", brightWhite: "#ffffff"
        )
        let map = SyntaxColorMap(theme: theme)

        // Verify each kind maps to a non-zero color
        let kinds: [TokenKind] = [.keyword, .string, .comment, .number, .type, .operator, .literal, .plain]
        for kind in kinds {
            let color = map.color(for: kind)
            XCTAssertNotEqual(color.w, 0, "Alpha should be non-zero for \(kind)")
        }
    }

    // MARK: - Helpers

    private func extractText(_ line: String, token: SyntaxToken) -> String {
        let utf16 = Array(line.utf16)
        let slice = Array(utf16[token.range])
        return String(utf16CodeUnits: slice, count: slice.count)
    }
}
