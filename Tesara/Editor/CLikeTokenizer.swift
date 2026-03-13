import Foundation

/// Language-specific keyword configuration for the C-like tokenizer.
struct LanguageConfig {
    let keywords: Set<String>
    let typeKeywords: Set<String>
    let literals: Set<String>

    // Pre-computed UTF-16 sets for allocation-free keyword lookup
    private(set) var keywordsUTF16: Set<[UInt16]> = []
    private(set) var typeKeywordsUTF16: Set<[UInt16]> = []
    private(set) var literalsUTF16: Set<[UInt16]> = []

    init(keywords: Set<String>, typeKeywords: Set<String>, literals: Set<String>) {
        self.keywords = keywords
        self.typeKeywords = typeKeywords
        self.literals = literals
        self.keywordsUTF16 = Set(keywords.map { Array($0.utf16) })
        self.typeKeywordsUTF16 = Set(typeKeywords.map { Array($0.utf16) })
        self.literalsUTF16 = Set(literals.map { Array($0.utf16) })
    }

    static let swift = LanguageConfig(
        keywords: ["func", "let", "var", "if", "else", "guard", "return", "switch", "case", "default",
                    "for", "while", "repeat", "break", "continue", "import", "class", "struct", "enum",
                    "protocol", "extension", "typealias", "init", "deinit", "self", "super", "throw",
                    "throws", "try", "catch", "do", "as", "is", "in", "where", "public", "private",
                    "internal", "fileprivate", "open", "static", "override", "final", "mutating",
                    "weak", "unowned", "lazy", "async", "await", "actor", "some", "any", "inout",
                    "defer", "associatedtype"],
        typeKeywords: ["Int", "String", "Bool", "Double", "Float", "Array", "Dictionary", "Set",
                       "Optional", "Result", "Void", "Any", "AnyObject", "Error", "Never",
                       "Character", "UInt", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16",
                       "UInt32", "UInt64", "CGFloat", "URL", "Data", "Date", "UUID"],
        literals: ["true", "false", "nil"]
    )

    static let javascript = LanguageConfig(
        keywords: ["function", "const", "let", "var", "if", "else", "return", "switch", "case",
                    "default", "for", "while", "do", "break", "continue", "import", "export",
                    "from", "class", "extends", "new", "this", "super", "throw", "try", "catch",
                    "finally", "typeof", "instanceof", "in", "of", "async", "await", "yield",
                    "delete", "void", "with", "debugger", "static", "get", "set"],
        typeKeywords: ["Array", "Object", "String", "Number", "Boolean", "Symbol", "BigInt",
                       "Map", "Set", "WeakMap", "WeakSet", "Promise", "Date", "RegExp",
                       "Error", "TypeError", "RangeError", "JSON", "Math", "console"],
        literals: ["true", "false", "null", "undefined", "NaN", "Infinity"]
    )

    static let typescript = LanguageConfig(
        keywords: javascript.keywords.union(["type", "interface", "enum", "namespace", "declare",
                                              "abstract", "implements", "readonly", "as", "is",
                                              "keyof", "infer", "satisfies"]),
        typeKeywords: javascript.typeKeywords.union(["string", "number", "boolean", "any", "unknown",
                                                     "never", "void", "object", "Record", "Partial",
                                                     "Required", "Readonly", "Pick", "Omit"]),
        literals: javascript.literals
    )

    static let go = LanguageConfig(
        keywords: ["func", "var", "const", "type", "struct", "interface", "if", "else", "for",
                    "range", "switch", "case", "default", "return", "break", "continue", "go",
                    "select", "chan", "defer", "fallthrough", "goto", "package", "import", "map",
                    "make", "new", "append", "len", "cap", "delete", "close", "copy"],
        typeKeywords: ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16",
                       "uint32", "uint64", "float32", "float64", "complex64", "complex128",
                       "string", "bool", "byte", "rune", "error", "any"],
        literals: ["true", "false", "nil", "iota"]
    )

    static let rust = LanguageConfig(
        keywords: ["fn", "let", "mut", "const", "if", "else", "match", "for", "while", "loop",
                    "break", "continue", "return", "use", "mod", "pub", "crate", "super", "self",
                    "struct", "enum", "trait", "impl", "type", "where", "as", "in", "ref",
                    "move", "async", "await", "dyn", "unsafe", "extern", "static", "macro_rules"],
        typeKeywords: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64",
                       "u128", "usize", "f32", "f64", "bool", "char", "str", "String",
                       "Vec", "Box", "Rc", "Arc", "Option", "Result", "Self"],
        literals: ["true", "false", "None", "Some", "Ok", "Err"]
    )

    static let c = LanguageConfig(
        keywords: ["if", "else", "for", "while", "do", "switch", "case", "default", "break",
                    "continue", "return", "goto", "typedef", "struct", "union", "enum", "extern",
                    "static", "const", "volatile", "register", "auto", "sizeof", "inline",
                    "#include", "#define", "#ifdef", "#ifndef", "#endif", "#if", "#else", "#pragma"],
        typeKeywords: ["int", "char", "float", "double", "void", "long", "short", "unsigned",
                       "signed", "size_t", "ssize_t", "uint8_t", "uint16_t", "uint32_t",
                       "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "bool",
                       "FILE", "NULL"],
        literals: ["true", "false", "NULL", "nullptr"]
    )

    static let java = LanguageConfig(
        keywords: ["class", "interface", "extends", "implements", "if", "else", "for", "while",
                    "do", "switch", "case", "default", "break", "continue", "return", "new",
                    "this", "super", "throw", "throws", "try", "catch", "finally", "import",
                    "package", "public", "private", "protected", "static", "final", "abstract",
                    "synchronized", "volatile", "transient", "native", "instanceof", "enum",
                    "assert", "void", "var", "yield", "sealed", "record", "permits"],
        typeKeywords: ["int", "long", "short", "byte", "float", "double", "char", "boolean",
                       "String", "Integer", "Long", "Double", "Float", "Boolean", "Character",
                       "Object", "Class", "List", "Map", "Set", "Optional", "Stream",
                       "Collection", "Iterable", "Comparable"],
        literals: ["true", "false", "null"]
    )
}

/// Hand-written lexical scanner for C-family languages.
/// Handles // and /* */ comments, string literals, numbers, keywords, and operators.
final class CLikeTokenizer: SyntaxTokenizer {
    let config: LanguageConfig

    init(config: LanguageConfig) {
        self.config = config
    }

    func tokenize(line: String, state: inout TokenizerState) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        let utf16 = Array(line.utf16)
        let len = utf16.count
        var i = 0

        // If we're in a block comment from a previous line, scan for */
        if state.inBlockComment {
            let start = i
            while i < len {
                if i + 1 < len && utf16[i] == 0x2A && utf16[i + 1] == 0x2F { // */
                    i += 2
                    state.inBlockComment = false
                    break
                }
                i += 1
            }
            tokens.append(SyntaxToken(range: start..<i, kind: .comment))
            if state.inBlockComment { return tokens } // entire line is comment
        }

        while i < len {
            let ch = utf16[i]

            // Skip whitespace
            if ch == 0x20 || ch == 0x09 || ch == 0x0D { // space, tab, CR
                i += 1
                continue
            }

            // Line comment: //
            if ch == 0x2F && i + 1 < len && utf16[i + 1] == 0x2F {
                tokens.append(SyntaxToken(range: i..<len, kind: .comment))
                return tokens
            }

            // Block comment: /*
            if ch == 0x2F && i + 1 < len && utf16[i + 1] == 0x2A {
                let start = i
                i += 2
                state.inBlockComment = true
                while i < len {
                    if i + 1 < len && utf16[i] == 0x2A && utf16[i + 1] == 0x2F {
                        i += 2
                        state.inBlockComment = false
                        break
                    }
                    i += 1
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .comment))
                continue
            }

            // String: "..." or '...'
            if ch == 0x22 || ch == 0x27 { // " or '
                let quote = ch
                let start = i
                i += 1
                while i < len {
                    if utf16[i] == 0x5C { // backslash escape
                        i += 2
                        continue
                    }
                    if utf16[i] == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .string))
                continue
            }

            // Backtick string (template literals for JS/TS)
            if ch == 0x60 { // `
                let start = i
                i += 1
                while i < len {
                    if utf16[i] == 0x5C { // backslash
                        i += 2
                        continue
                    }
                    if utf16[i] == 0x60 {
                        i += 1
                        break
                    }
                    i += 1
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .string))
                continue
            }

            // Number
            if isDigit(ch) || (ch == 0x2E && i + 1 < len && isDigit(utf16[i + 1])) {
                let start = i
                // Handle 0x, 0b, 0o prefixes
                if ch == 0x30 && i + 1 < len {
                    let next = utf16[i + 1]
                    if next == 0x78 || next == 0x58 || next == 0x62 || next == 0x42 || next == 0x6F || next == 0x4F {
                        i += 2
                    }
                }
                while i < len && (isDigit(utf16[i]) || utf16[i] == 0x2E || utf16[i] == 0x5F ||
                                   utf16[i] == 0x65 || utf16[i] == 0x45 || // e, E
                                   isHexDigit(utf16[i])) {
                    i += 1
                }
                tokens.append(SyntaxToken(range: start..<i, kind: .number))
                continue
            }

            // Preprocessor: #
            if ch == 0x23 { // #
                let start = i
                i += 1
                while i < len && isIdentChar(utf16[i]) { i += 1 }
                let wordUTF16 = Array(utf16[start..<i])
                if config.keywordsUTF16.contains(wordUTF16) {
                    tokens.append(SyntaxToken(range: start..<i, kind: .keyword))
                } else {
                    tokens.append(SyntaxToken(range: start..<i, kind: .plain))
                }
                continue
            }

            // Identifier or keyword
            if isIdentStart(ch) {
                let start = i
                i += 1
                while i < len && isIdentChar(utf16[i]) { i += 1 }
                let wordUTF16 = Array(utf16[start..<i])
                if config.keywordsUTF16.contains(wordUTF16) {
                    tokens.append(SyntaxToken(range: start..<i, kind: .keyword))
                } else if config.literalsUTF16.contains(wordUTF16) {
                    tokens.append(SyntaxToken(range: start..<i, kind: .literal))
                } else if config.typeKeywordsUTF16.contains(wordUTF16) {
                    tokens.append(SyntaxToken(range: start..<i, kind: .type))
                } else {
                    tokens.append(SyntaxToken(range: start..<i, kind: .plain))
                }
                continue
            }

            // Operators
            if isOperatorChar(ch) {
                let start = i
                i += 1
                // Multi-char operators
                while i < len && isOperatorChar(utf16[i]) && !isBracket(utf16[i]) { i += 1 }
                tokens.append(SyntaxToken(range: start..<i, kind: .operator))
                continue
            }

            // Brackets and other punctuation
            i += 1
        }

        return tokens
    }

    // MARK: - Character Classification

    private func isDigit(_ ch: UInt16) -> Bool {
        ch >= 0x30 && ch <= 0x39
    }

    private func isHexDigit(_ ch: UInt16) -> Bool {
        isDigit(ch) || (ch >= 0x41 && ch <= 0x46) || (ch >= 0x61 && ch <= 0x66)
    }

    private func isIdentStart(_ ch: UInt16) -> Bool {
        (ch >= 0x41 && ch <= 0x5A) || // A-Z
        (ch >= 0x61 && ch <= 0x7A) || // a-z
        ch == 0x5F ||                   // _
        ch == 0x24 ||                   // $ (JS)
        ch == 0x40                      // @ (decorators)
    }

    private func isIdentChar(_ ch: UInt16) -> Bool {
        isIdentStart(ch) || isDigit(ch)
    }

    private func isOperatorChar(_ ch: UInt16) -> Bool {
        switch ch {
        case 0x2B, 0x2D, 0x2A, 0x2F, 0x25, // + - * / %
             0x3D, 0x21, 0x3C, 0x3E,         // = ! < >
             0x26, 0x7C, 0x5E, 0x7E,         // & | ^ ~
             0x3F,                             // ?
             0x28, 0x29, 0x5B, 0x5D,         // ( ) [ ]
             0x7B, 0x7D,                       // { }
             0x2C, 0x3B, 0x3A, 0x2E:         // , ; : .
            return true
        default:
            return false
        }
    }

    private func isBracket(_ ch: UInt16) -> Bool {
        ch == 0x28 || ch == 0x29 || ch == 0x5B || ch == 0x5D || ch == 0x7B || ch == 0x7D
    }
}
