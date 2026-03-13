import Foundation

/// Hand-written lexical scanner for JSON files.
/// Handles strings (with escapes), numbers, null/true/false, and structural characters.
final class JSONTokenizer: SyntaxTokenizer {

    func tokenize(line: String, state: inout TokenizerState) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let utf16 = Array(line.utf16)
        let len = utf16.count
        var i = 0

        while i < len {
            let ch = utf16[i]

            // Skip whitespace
            if ch == 0x20 || ch == 0x09 || ch == 0x0D || ch == 0x0A {
                i += 1
                continue
            }

            // String: "..."
            if ch == 0x22 { // "
                let start = i
                i += 1
                while i < len {
                    if utf16[i] == 0x5C { // backslash escape
                        i += 2
                        continue
                    }
                    if utf16[i] == 0x22 {
                        i += 1
                        break
                    }
                    i += 1
                }
                // Check if this is a key (followed by :)
                var j = i
                while j < len && (utf16[j] == 0x20 || utf16[j] == 0x09) { j += 1 }
                if j < len && utf16[j] == 0x3A { // :
                    tokens.append(SyntaxToken(range: start..<i, kind: .keyword))
                } else {
                    tokens.append(SyntaxToken(range: start..<i, kind: .string))
                }
                continue
            }

            // Number
            if isDigit(ch) || ch == 0x2D { // digit or -
                let start = i
                if ch == 0x2D { i += 1 }
                while i < len && isDigit(utf16[i]) { i += 1 }
                if i < len && utf16[i] == 0x2E { // .
                    i += 1
                    while i < len && isDigit(utf16[i]) { i += 1 }
                }
                if i < len && (utf16[i] == 0x65 || utf16[i] == 0x45) { // e or E
                    i += 1
                    if i < len && (utf16[i] == 0x2B || utf16[i] == 0x2D) { i += 1 } // + or -
                    while i < len && isDigit(utf16[i]) { i += 1 }
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .number))
                continue
            }

            // Literals: true, false, null
            if ch == 0x74 && matchesLiteral(utf16: utf16, at: i, literal: [0x74, 0x72, 0x75, 0x65]) { // true
                tokens.append(SyntaxToken(range: i..<(i + 4), kind: .literal))
                i += 4
                continue
            }
            if ch == 0x66 && matchesLiteral(utf16: utf16, at: i, literal: [0x66, 0x61, 0x6C, 0x73, 0x65]) { // false
                tokens.append(SyntaxToken(range: i..<(i + 5), kind: .literal))
                i += 5
                continue
            }
            if ch == 0x6E && matchesLiteral(utf16: utf16, at: i, literal: [0x6E, 0x75, 0x6C, 0x6C]) { // null
                tokens.append(SyntaxToken(range: i..<(i + 4), kind: .literal))
                i += 4
                continue
            }

            // Structural characters: { } [ ] , :
            i += 1
        }

        return tokens
    }

    private func isDigit(_ ch: UInt16) -> Bool {
        ch >= 0x30 && ch <= 0x39
    }

    private func matchesLiteral(utf16: [UInt16], at index: Int, literal: [UInt16]) -> Bool {
        guard index + literal.count <= utf16.count else { return false }
        for (j, expected) in literal.enumerated() {
            if utf16[index + j] != expected { return false }
        }
        // Ensure the literal is not part of a longer identifier
        let afterIndex = index + literal.count
        if afterIndex < utf16.count {
            let next = utf16[afterIndex]
            if (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A) ||
                (next >= 0x30 && next <= 0x39) || next == 0x5F {
                return false
            }
        }
        return true
    }
}
