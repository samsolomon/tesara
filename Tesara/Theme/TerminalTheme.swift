import SwiftUI

struct TerminalTheme: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var foreground: String
    var background: String
    var cursor: String
    var cursorText: String
    var selectionBackground: String
    var selectionForeground: String?
    var black: String
    var red: String
    var green: String
    var yellow: String
    var blue: String
    var magenta: String
    var cyan: String
    var white: String
    var brightBlack: String
    var brightRed: String
    var brightGreen: String
    var brightYellow: String
    var brightBlue: String
    var brightMagenta: String
    var brightCyan: String
    var brightWhite: String
    var linkColor: String?
}

extension TerminalTheme {
    var swiftUIBackgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                swiftUIColor(from: background),
                swiftUIColor(from: blue).opacity(0.35)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func swiftUIColor(from hex: String) -> Color {
        Color(hex: hex) ?? .black
    }

    var isDarkBackground: Bool {
        luminance(of: background) < 0.5
    }

    private func luminance(of hex: String) -> Double {
        let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let intValue = UInt64(sanitized, radix: 16) else {
            return 0
        }
        let r = Double((intValue & 0xFF0000) >> 16) / 255.0
        let g = Double((intValue & 0x00FF00) >> 8) / 255.0
        let b = Double(intValue & 0x0000FF) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension Color {
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        guard sanitized.count == 6, let intValue = UInt64(sanitized, radix: 16) else {
            return nil
        }

        let red = Double((intValue & 0xFF0000) >> 16) / 255.0
        let green = Double((intValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(intValue & 0x0000FF) / 255.0

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
