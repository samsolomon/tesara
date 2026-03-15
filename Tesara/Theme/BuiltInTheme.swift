import Foundation

enum BuiltInTheme: String, CaseIterable {
    case tesaraDark
    case tesaraLight
    case oxideDark
    case oxideLight
    case atlasDark
    case atlasLight
    case emberDark
    case emberLight
    case tideDark
    case tideLight
    case groveDark
    case groveLight
    case brassDark
    case brassLight
    case duskDark
    case duskLight
    case paperDark
    case paperLight
    case signalDark
    case signalLight
    case slateDark
    case slateLight

    var id: String { rawValue }

    var theme: TerminalTheme {
        switch self {
        case .tesaraDark:
            TerminalTheme(
                id: id,
                name: "Tesara Dark",
                foreground: "#EAE6E1",
                background: "#111018",
                cursor: "#E07A5F",
                cursorText: "#111018",
                selectionBackground: "#332F42",
                selectionForeground: "#EAE6E1",
                black: "#1B1924",
                red: "#BF6060",
                green: "#6BAF7A",
                yellow: "#D4A054",
                blue: "#5FA0B4",
                magenta: "#A07DA8",
                cyan: "#5FACA0",
                white: "#EAE6E1",
                brightBlack: "#857E93",
                brightRed: "#E08A7A",
                brightGreen: "#8ECFA0",
                brightYellow: "#E8C080",
                brightBlue: "#7BBDD0",
                brightMagenta: "#C49ABC",
                brightCyan: "#7ECEC0",
                brightWhite: "#F5F3F0",
                linkColor: "#5FA0B4"
            )
        case .tesaraLight:
            TerminalTheme(
                id: id,
                name: "Tesara Light",
                foreground: "#1B1924",
                background: "#F5F3F0",
                cursor: "#D06B4F",
                cursorText: "#F5F3F0",
                selectionBackground: "#DDD8D2",
                selectionForeground: "#1B1924",
                black: "#1B1924",
                red: "#B04F4F",
                green: "#4E8F5C",
                yellow: "#B8882E",
                blue: "#4A8A9E",
                magenta: "#8A6485",
                cyan: "#4A9E90",
                white: "#EAE6E1",
                brightBlack: "#6E6880",
                brightRed: "#D06B4F",
                brightGreen: "#6BAF7A",
                brightYellow: "#D4A054",
                brightBlue: "#5FA0B4",
                brightMagenta: "#A87DA0",
                brightCyan: "#6BBFB0",
                brightWhite: "#FFFFFF",
                linkColor: "#4A8A9E"
            )
        case .oxideDark:
            makeTheme(name: "Oxide Dark", background: "#111827", foreground: "#E5E7EB", accent: "#F59E0B")
        case .oxideLight:
            makeTheme(name: "Oxide Light", background: "#FAFAF8", foreground: "#111827", accent: "#B45309", light: true)
        case .atlasDark:
            makeTheme(name: "Atlas Dark", background: "#0F172A", foreground: "#E2E8F0", accent: "#0EA5E9")
        case .atlasLight:
            makeTheme(name: "Atlas Light", background: "#F0F4FA", foreground: "#0F172A", accent: "#0369A1", light: true)
        case .emberDark:
            makeTheme(name: "Ember Dark", background: "#1C1917", foreground: "#F5F5F4", accent: "#EA580C")
        case .emberLight:
            makeTheme(name: "Ember Light", background: "#FBF7F5", foreground: "#1C1917", accent: "#C2410C", light: true)
        case .tideDark:
            makeTheme(name: "Tide Dark", background: "#082F49", foreground: "#E0F2FE", accent: "#06B6D4")
        case .tideLight:
            makeTheme(name: "Tide Light", background: "#F0FAFE", foreground: "#082F49", accent: "#0E7490", light: true)
        case .groveDark:
            makeTheme(name: "Grove Dark", background: "#052E16", foreground: "#DCFCE7", accent: "#22C55E")
        case .groveLight:
            makeTheme(name: "Grove Light", background: "#F0FAF4", foreground: "#052E16", accent: "#15803D", light: true)
        case .brassDark:
            makeTheme(name: "Brass Dark", background: "#1F2937", foreground: "#F9FAFB", accent: "#D97706")
        case .brassLight:
            makeTheme(name: "Brass Light", background: "#FAF8F0", foreground: "#1F2937", accent: "#92400E", light: true)
        case .duskDark:
            makeTheme(name: "Dusk Dark", background: "#1E1B4B", foreground: "#EDE9FE", accent: "#818CF8")
        case .duskLight:
            makeTheme(name: "Dusk Light", background: "#F2F0FA", foreground: "#1E1B4B", accent: "#4F46E5", light: true)
        case .paperDark:
            makeTheme(name: "Paper Dark", background: "#1A1B2E", foreground: "#F8FAFC", accent: "#2563EB")
        case .paperLight:
            makeTheme(name: "Paper Light", background: "#F8FAFC", foreground: "#0F172A", accent: "#1D4ED8", light: true)
        case .signalDark:
            makeTheme(name: "Signal Dark", background: "#18181B", foreground: "#FAFAFA", accent: "#E11D48")
        case .signalLight:
            makeTheme(name: "Signal Light", background: "#FEF2F2", foreground: "#18181B", accent: "#BE123C", light: true)
        case .slateDark:
            makeTheme(name: "Slate Dark", background: "#0F172A", foreground: "#CBD5E1", accent: "#64748B")
        case .slateLight:
            makeTheme(name: "Slate Light", background: "#F1F5F9", foreground: "#0F172A", accent: "#475569", light: true)
        }
    }

    private func makeTheme(name: String, background: String, foreground: String, accent: String, light: Bool = false) -> TerminalTheme {
        TerminalTheme(
            id: id,
            name: name,
            foreground: foreground,
            background: background,
            cursor: accent,
            cursorText: background,
            selectionBackground: light ? "#CBD5E1" : "#334155",
            selectionForeground: foreground,
            black: light ? "#334155" : "#0F172A",
            red: light ? "#DC2626" : "#EF4444",
            green: light ? "#16A34A" : "#22C55E",
            yellow: light ? "#CA8A04" : "#EAB308",
            blue: light ? "#2563EB" : "#3B82F6",
            magenta: light ? "#9333EA" : "#A855F7",
            cyan: light ? "#0891B2" : "#06B6D4",
            white: light ? "#E2E8F0" : "#E5E7EB",
            brightBlack: light ? "#64748B" : "#475569",
            brightRed: light ? "#EF4444" : "#F87171",
            brightGreen: light ? "#22C55E" : "#4ADE80",
            brightYellow: light ? "#EAB308" : "#FACC15",
            brightBlue: light ? "#3B82F6" : "#60A5FA",
            brightMagenta: light ? "#A855F7" : "#C084FC",
            brightCyan: light ? "#06B6D4" : "#22D3EE",
            brightWhite: light ? "#FFFFFF" : "#F8FAFC",
            linkColor: accent
        )
    }
}
