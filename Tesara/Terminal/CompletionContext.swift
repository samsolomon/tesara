import Foundation

enum CompletionContext: Equatable {
    case command
    case filePath
    case gitBranch

    /// Git subcommands that take branch names as arguments.
    private static let gitBranchSubcommands: Set<String> = [
        "checkout", "switch", "merge", "rebase", "branch", "cherry-pick",
    ]

    /// Analyze the current line up to the cursor and determine the completion context.
    /// Returns the context type, the UTF-16 column where the current token starts,
    /// and the prefix text to complete.
    static func detect(lineText: String, cursorColumn: Int) -> (context: CompletionContext, tokenStart: Int, prefix: String) {
        let utf16 = Array(lineText.utf16)
        let cursor = min(cursorColumn, utf16.count)

        // Tokenize up to cursor into shell-like tokens
        let tokens = tokenize(utf16: utf16, upTo: cursor)

        guard let lastToken = tokens.last else {
            // Empty line or cursor at start — command context with empty prefix
            return (.command, cursor, "")
        }

        // Check if cursor is immediately after the last token (no trailing space)
        let cursorOnToken = lastToken.end == cursor

        if !cursorOnToken {
            // Cursor is after whitespace — starting a new token
            let position = tokenPosition(tokens: tokens, utf16: utf16, upTo: cursor)
            let context = contextForPosition(position)
            return (context, cursor, "")
        }

        // Cursor is on the last token — completing it
        let position = tokenPosition(tokens: tokens, utf16: utf16, upTo: cursor)
        let context = contextForPosition(position)
        let prefixStr = extractString(from: utf16, start: lastToken.start, end: lastToken.end)
        return (context, lastToken.start, prefixStr)
    }

    // MARK: - Token

    private struct Token {
        let start: Int   // UTF-16 offset
        let end: Int     // UTF-16 offset
        let text: String
        let isOperator: Bool
    }

    private enum TokenPosition {
        case first               // First token in a command pipeline segment
        case afterGitBranch      // After "git checkout/switch/merge/..." subcommand
        case argument            // Everything else (argument position)
    }

    // MARK: - Tokenizer

    private static func tokenize(utf16: [UInt16], upTo limit: Int) -> [Token] {
        var tokens: [Token] = []
        var i = 0

        while i < limit {
            let ch = utf16[i]

            // Skip whitespace
            if ch == 0x20 || ch == 0x09 {
                i += 1
                continue
            }

            // Single-quoted string
            if ch == 0x27 {
                let start = i
                i += 1
                while i < limit && utf16[i] != 0x27 { i += 1 }
                if i < limit { i += 1 }
                tokens.append(Token(start: start, end: i, text: extractString(from: utf16, start: start, end: i), isOperator: false))
                continue
            }

            // Double-quoted string
            if ch == 0x22 {
                let start = i
                i += 1
                while i < limit {
                    if utf16[i] == 0x5C && i + 1 < limit { i += 2; continue }
                    if utf16[i] == 0x22 { i += 1; break }
                    i += 1
                }
                tokens.append(Token(start: start, end: i, text: extractString(from: utf16, start: start, end: i), isOperator: false))
                continue
            }

            // Multi-char operators: ||, &&
            if i + 1 < limit {
                let next = utf16[i + 1]
                if (ch == 0x7C && next == 0x7C) || (ch == 0x26 && next == 0x26) {
                    tokens.append(Token(start: i, end: i + 2, text: extractString(from: utf16, start: i, end: i + 2), isOperator: true))
                    i += 2
                    continue
                }
            }

            // Single-char operators that start new command: | ;
            if ch == 0x7C || ch == 0x3B {
                tokens.append(Token(start: i, end: i + 1, text: extractString(from: utf16, start: i, end: i + 1), isOperator: true))
                i += 1
                continue
            }

            // Word characters (including backslash-escaped characters)
            if isWordChar(ch) {
                let start = i
                i += 1
                while i < limit {
                    let c = utf16[i]
                    if c == 0x5C && i + 1 < limit { // backslash escape
                        i += 2
                        continue
                    }
                    if !isWordChar(c) { break }
                    i += 1
                }
                tokens.append(Token(start: start, end: i, text: extractString(from: utf16, start: start, end: i), isOperator: false))
                continue
            }

            // Skip unrecognized
            i += 1
        }

        return tokens
    }

    private static func isWordChar(_ ch: UInt16) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) || // A-Z
        (ch >= 0x61 && ch <= 0x7A) || // a-z
        (ch >= 0x30 && ch <= 0x39) || // 0-9
        ch == 0x5F || // _
        ch == 0x2F || // /
        ch == 0x2E || // .
        ch == 0x7E || // ~
        ch == 0x2D || // -
        ch == 0x3A || // :
        ch == 0x40 || // @
        ch == 0x3D || // =
        ch == 0x5C || // backslash
        ch == 0x2B || // +
        ch == 0x25 || // %
        ch == 0x2C || // ,
        ch == 0x5B || // [
        ch == 0x5D || // ]
        ch == 0x23 || // #
        ch == 0x7B || // {
        ch == 0x7D    // }
    }

    private static func extractString(from utf16: [UInt16], start: Int, end: Int) -> String {
        let slice = Array(utf16[start..<end])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    // MARK: - Position Detection

    /// Determine token position by finding the last operator and counting non-operator tokens after it.
    private static func tokenPosition(tokens: [Token], utf16: [UInt16], upTo cursor: Int) -> TokenPosition {
        // Find the last operator — tokens after it form the current "simple command"
        var commandTokens: [Token] = []
        for token in tokens.reversed() {
            if token.isOperator { break }
            commandTokens.append(token)
        }
        commandTokens.reverse()

        if commandTokens.isEmpty {
            return .first
        }

        // If cursor is past the last token (whitespace after), we're starting a new token
        let cursorOnLastToken = commandTokens.last.map { $0.end == cursor } ?? false

        let tokenCount: Int
        if cursorOnLastToken {
            tokenCount = commandTokens.count
        } else {
            // Starting a new token after whitespace
            tokenCount = commandTokens.count + 1
        }

        if tokenCount <= 1 {
            return .first
        }

        // Check for git branch context
        if commandTokens.count >= 2 {
            let first = commandTokens[0].text
            if first == "git" || first.hasSuffix("/git") {
                let subcommand = commandTokens[1].text
                if gitBranchSubcommands.contains(subcommand) {
                    // After "git checkout <flags> ..." — if we're past the subcommand
                    // and any flags, we're in branch context
                    if cursorOnLastToken {
                        if commandTokens.count >= 3 {
                            let lastTok = commandTokens[commandTokens.count - 1]
                            if !lastTok.text.hasPrefix("-") {
                                return .afterGitBranch
                            }
                        }
                    } else {
                        // Starting new token after existing tokens
                        if tokenCount > 2 {
                            return .afterGitBranch
                        }
                    }
                }
            }
        }

        return .argument
    }

    private static func contextForPosition(_ position: TokenPosition) -> CompletionContext {
        switch position {
        case .first: return .command
        case .afterGitBranch: return .gitBranch
        case .argument: return .filePath
        }
    }
}
