import Foundation

/// Lexical scanner for shell commands (bash/zsh).
/// Highlights commands, flags, strings, variables, operators, and comments.
final class ShellTokenizer: SyntaxTokenizer {

    func tokenize(line: String, state: inout TokenizerState) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let utf16 = Array(line.utf16)
        let len = utf16.count
        var i = 0
        var nextIsCommand = true

        while i < len {
            let ch = utf16[i]

            // Skip whitespace
            if ch == 0x20 || ch == 0x09 { // space, tab
                i += 1
                continue
            }

            // Comment: # to end of line
            if ch == 0x23 { // #
                tokens.append(SyntaxToken(range: i..<len, kind: .comment))
                return tokens
            }

            // Single-quoted string: '...' (no escapes)
            if ch == 0x27 { // '
                let start = i
                i += 1
                while i < len && utf16[i] != 0x27 { i += 1 }
                if i < len { i += 1 } // consume closing '
                tokens.append(SyntaxToken(range: start..<i, kind: .string))
                nextIsCommand = false
                continue
            }

            // Double-quoted string: "..." (with escapes)
            if ch == 0x22 { // "
                let start = i
                i += 1
                while i < len {
                    if utf16[i] == 0x5C && i + 1 < len { // backslash escape
                        i += 2
                        continue
                    }
                    if utf16[i] == 0x22 { // closing "
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .string))
                nextIsCommand = false
                continue
            }

            // Variable: $VAR, ${VAR}, $(cmd), $0-$9, $?, $!, etc.
            if ch == 0x24 { // $
                let start = i

                guard i + 1 < len else {
                    // Lone $ at end of line
                    tokens.append(SyntaxToken(range: i..<i + 1, kind: .plain))
                    i += 1
                    continue
                }

                let next = utf16[i + 1]

                if next == 0x7B { // ${...}
                    i += 2
                    while i < len && utf16[i] != 0x7D { i += 1 } // scan to }
                    if i < len { i += 1 }
                    tokens.append(SyntaxToken(range: start..<i, kind: .type))
                    nextIsCommand = false
                    continue
                }

                if next == 0x28 { // $(...)
                    i += 2
                    var depth = 1
                    while i < len && depth > 0 {
                        if utf16[i] == 0x28 { depth += 1 }
                        else if utf16[i] == 0x29 { depth -= 1 }
                        if depth > 0 { i += 1 }
                    }
                    if i < len { i += 1 } // consume closing )
                    tokens.append(SyntaxToken(range: start..<i, kind: .type))
                    nextIsCommand = false
                    continue
                }

                if isIdentStart(next) {
                    // $VAR — identifier variable
                    i += 2
                    while i < len && isIdentChar(utf16[i]) { i += 1 }
                    tokens.append(SyntaxToken(range: start..<i, kind: .type))
                    nextIsCommand = false
                    continue
                }

                if (next >= 0x30 && next <= 0x39) || // $0-$9
                   next == 0x3F || next == 0x21 ||    // $? $!
                   next == 0x24 || next == 0x40 ||    // $$ $@
                   next == 0x2A || next == 0x23 ||    // $* $#
                   next == 0x2D {                     // $-
                    tokens.append(SyntaxToken(range: start..<i + 2, kind: .type))
                    i += 2
                    nextIsCommand = false
                    continue
                }

                // $ followed by unrecognized char — emit as plain
                tokens.append(SyntaxToken(range: i..<i + 1, kind: .plain))
                i += 1
                continue
            }

            // Multi-char operators: ||, &&, >>, <<
            if i + 1 < len {
                let next = utf16[i + 1]
                if (ch == 0x7C && next == 0x7C) || // ||
                   (ch == 0x26 && next == 0x26) || // &&
                   (ch == 0x3E && next == 0x3E) || // >>
                   (ch == 0x3C && next == 0x3C) {  // <<
                    tokens.append(SyntaxToken(range: i..<i + 2, kind: .operator))
                    i += 2
                    nextIsCommand = (ch == 0x7C || ch == 0x26) // || and && start new command
                    continue
                }
            }

            // Single-char operators: | & ; < > ( )
            if ch == 0x7C || ch == 0x26 || ch == 0x3B || ch == 0x3C || ch == 0x3E { // | & ; < >
                tokens.append(SyntaxToken(range: i..<i + 1, kind: .operator))
                i += 1
                nextIsCommand = (ch == 0x7C || ch == 0x3B || ch == 0x26) // | ; & start new command
                continue
            }

            if ch == 0x28 { // (
                tokens.append(SyntaxToken(range: i..<i + 1, kind: .operator))
                i += 1
                nextIsCommand = true
                continue
            }

            if ch == 0x29 { // )
                tokens.append(SyntaxToken(range: i..<i + 1, kind: .operator))
                i += 1
                nextIsCommand = false
                continue
            }

            // Flag: -x, --long-option
            if ch == 0x2D && nextIsNotMinus(utf16, i, len) { // -
                let start = i
                i += 1
                while i < len && isFlagChar(utf16[i]) { i += 1 }
                if i > start + 1 { // at least one char after -
                    tokens.append(SyntaxToken(range: start..<i, kind: .literal))
                    nextIsCommand = false
                    continue
                }
                // lone - is just a word
                i = start
            }

            // Word (command or argument)
            if isWordChar(ch) || ch == 0x2D { // includes -
                let start = i
                i += 1
                while i < len && isWordContinue(utf16[i]) { i += 1 }

                if nextIsCommand {
                    // Check if this is a variable assignment (word contains =)
                    if containsEquals(utf16, start, i) {
                        tokens.append(SyntaxToken(range: start..<i, kind: .plain))
                        // nextIsCommand stays true — actual command follows
                    } else {
                        tokens.append(SyntaxToken(range: start..<i, kind: .keyword))
                        nextIsCommand = false
                    }
                } else if isAllDigits(utf16, start, i) {
                    tokens.append(SyntaxToken(range: start..<i, kind: .number))
                } else {
                    tokens.append(SyntaxToken(range: start..<i, kind: .plain))
                }
                continue
            }

            // Skip unrecognized character
            i += 1
        }

        return tokens
    }

    // MARK: - Character Classification

    private func isIdentStart(_ ch: UInt16) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) || // A-Z
        (ch >= 0x61 && ch <= 0x7A) || // a-z
        ch == 0x5F                     // _
    }

    private func isIdentChar(_ ch: UInt16) -> Bool {
        isIdentStart(ch) || (ch >= 0x30 && ch <= 0x39) // + 0-9
    }

    private func isWordChar(_ ch: UInt16) -> Bool {
        isIdentChar(ch) ||
        ch == 0x2F || // /
        ch == 0x2E || // .
        ch == 0x7E || // ~
        ch == 0x3A || // :
        ch == 0x40 || // @
        ch == 0x5B || // [
        ch == 0x5D || // ]
        ch == 0x2B || // +
        ch == 0x25 || // %
        ch == 0x2C || // ,
        ch == 0x5C    // backslash (escaped chars in paths)
    }

    private func isWordContinue(_ ch: UInt16) -> Bool {
        isWordChar(ch) ||
        ch == 0x2D || // -
        ch == 0x3D    // = (for key=value args like --flag=val)
    }

    private func isFlagChar(_ ch: UInt16) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) || // A-Z
        (ch >= 0x61 && ch <= 0x7A) || // a-z
        (ch >= 0x30 && ch <= 0x39) || // 0-9
        ch == 0x2D || // -
        ch == 0x5F    // _
    }

    private func nextIsNotMinus(_ utf16: [UInt16], _ i: Int, _ len: Int) -> Bool {
        i + 1 < len && isFlagChar(utf16[i + 1])
    }

    private func isAllDigits(_ utf16: [UInt16], _ start: Int, _ end: Int) -> Bool {
        guard end > start else { return false }
        for k in start..<end {
            let c = utf16[k]
            if c < 0x30 || c > 0x39 { return false }
        }
        return true
    }

    private func containsEquals(_ utf16: [UInt16], _ start: Int, _ end: Int) -> Bool {
        for k in start..<end {
            if utf16[k] == 0x3D { return true }
        }
        return false
    }
}
