import Foundation

// MARK: - Token Types

enum TokenKind {
    case keyword
    case string
    case comment
    case number
    case type
    case `operator`
    case literal
    case plain
}

struct SyntaxToken {
    let range: Range<Int>  // UTF-16 offset within the line
    let kind: TokenKind
}

// MARK: - Tokenizer Protocol

protocol SyntaxTokenizer {
    func tokenize(line: String, state: inout TokenizerState) -> [SyntaxToken]
}

struct TokenizerState: Equatable {
    var inBlockComment: Bool = false
    var inMultiLineString: Bool = false
}

// MARK: - Syntax Highlighter

@MainActor
final class SyntaxHighlighter {

    private let tokenizer: SyntaxTokenizer?
    private var lineTokens: [Int: [SyntaxToken]] = [:]
    private var lineEndStates: [Int: TokenizerState] = [:]
    private var staleFromLine: Int?

    init(fileExtension: String) {
        self.tokenizer = Self.tokenizerForExtension(fileExtension)
    }

    init(tokenizer: SyntaxTokenizer) {
        self.tokenizer = tokenizer
    }

    var isActive: Bool { tokenizer != nil }

    func tokens(forLine lineIndex: Int) -> [SyntaxToken]? {
        lineTokens[lineIndex]
    }

    func fullTokenize(storage: TextStorage) {
        guard let tokenizer else { return }
        lineTokens.removeAll()
        lineEndStates.removeAll()
        staleFromLine = nil

        var state = TokenizerState()
        for i in 0..<storage.lineCount {
            let content = storage.lineContent(i)
            let tokens = tokenizer.tokenize(line: content, state: &state)
            lineTokens[i] = tokens
            lineEndStates[i] = state
        }
    }

    func invalidateLines(from lineIndex: Int, storage: TextStorage, lastVisibleLine: Int) {
        guard let tokenizer else { return }
        let maxCascade = lastVisibleLine + 200

        // Get the state from the previous line
        var state: TokenizerState
        if lineIndex > 0, let prev = lineEndStates[lineIndex - 1] {
            state = prev
        } else {
            state = TokenizerState()
        }

        var line = lineIndex
        while line < min(storage.lineCount, maxCascade) {
            let oldEndState = lineEndStates[line]
            let content = storage.lineContent(line)
            let tokens = tokenizer.tokenize(line: content, state: &state)
            lineTokens[line] = tokens
            lineEndStates[line] = state
            if oldEndState == state { break }  // converged
            line += 1
        }

        if line >= maxCascade {
            staleFromLine = line
        }
    }

    func ensureTokenized(throughLine lastLine: Int, storage: TextStorage) {
        guard let tokenizer, let stale = staleFromLine, stale <= lastLine else { return }

        var state: TokenizerState
        if stale > 0, let prev = lineEndStates[stale - 1] {
            state = prev
        } else {
            state = TokenizerState()
        }

        for line in stale...min(lastLine, storage.lineCount - 1) {
            let content = storage.lineContent(line)
            let tokens = tokenizer.tokenize(line: content, state: &state)
            lineTokens[line] = tokens
            lineEndStates[line] = state
        }

        staleFromLine = lastLine + 1 < storage.lineCount ? lastLine + 1 : nil
    }

    // MARK: - Extension Mapping

    private static func tokenizerForExtension(_ ext: String) -> SyntaxTokenizer? {
        switch ext.lowercased() {
        case "swift":
            return CLikeTokenizer(config: .swift)
        case "js", "jsx":
            return CLikeTokenizer(config: .javascript)
        case "ts", "tsx":
            return CLikeTokenizer(config: .typescript)
        case "go":
            return CLikeTokenizer(config: .go)
        case "rs":
            return CLikeTokenizer(config: .rust)
        case "c", "h":
            return CLikeTokenizer(config: .c)
        case "cpp", "cc", "cxx", "hpp":
            return CLikeTokenizer(config: .c)
        case "java":
            return CLikeTokenizer(config: .java)
        case "cs":
            return CLikeTokenizer(config: .java)
        case "json":
            return JSONTokenizer()
        case "sh", "bash", "zsh":
            return ShellTokenizer()
        default:
            return nil
        }
    }
}
