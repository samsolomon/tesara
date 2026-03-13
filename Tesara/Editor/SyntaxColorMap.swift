import Foundation

/// Parses a hex color string (e.g. "#ff00ff" or "ff00ff") into SIMD4<UInt8>.
func hexToColorU8(_ hex: String, alpha: UInt8 = 255) -> SIMD4<UInt8> {
    let sanitized = hex.replacingOccurrences(of: "#", with: "")
    guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
        return SIMD4<UInt8>(204, 204, 204, alpha)
    }
    return SIMD4<UInt8>(
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF),
        alpha
    )
}

/// Maps syntax token kinds to colors derived from the terminal theme's ANSI palette.
struct SyntaxColorMap {
    let keyword: SIMD4<UInt8>     // blue
    let string: SIMD4<UInt8>      // green
    let comment: SIMD4<UInt8>     // bright black
    let number: SIMD4<UInt8>      // magenta
    let type: SIMD4<UInt8>        // yellow
    let `operator`: SIMD4<UInt8>  // red
    let literal: SIMD4<UInt8>     // cyan
    let plain: SIMD4<UInt8>       // foreground

    init(theme: TerminalTheme) {
        self.keyword = hexToColorU8(theme.blue)
        self.string = hexToColorU8(theme.green)
        self.comment = hexToColorU8(theme.brightBlack)
        self.number = hexToColorU8(theme.magenta)
        self.type = hexToColorU8(theme.yellow)
        self.operator = hexToColorU8(theme.red)
        self.literal = hexToColorU8(theme.cyan)
        self.plain = hexToColorU8(theme.foreground)
    }

    func color(for kind: TokenKind) -> SIMD4<UInt8> {
        switch kind {
        case .keyword: return keyword
        case .string: return string
        case .comment: return comment
        case .number: return number
        case .type: return type
        case .operator: return `operator`
        case .literal: return literal
        case .plain: return plain
        }
    }
}
