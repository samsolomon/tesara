import Foundation

enum BuiltInTheme: String, CaseIterable {
    case oxide
    case atlas
    case ember
    case tide
    case grove
    case brass
    case dusk
    case paper
    case signal
    case slate

    var id: String { rawValue }

    var theme: TerminalTheme {
        switch self {
        case .oxide:
            TerminalTheme(
                id: id,
                name: "Oxide",
                foreground: "#E5E7EB",
                background: "#111827",
                cursor: "#F59E0B",
                cursorText: "#111827",
                selectionBackground: "#374151",
                selectionForeground: "#F9FAFB",
                black: "#111827",
                red: "#F87171",
                green: "#34D399",
                yellow: "#FBBF24",
                blue: "#60A5FA",
                magenta: "#C084FC",
                cyan: "#22D3EE",
                white: "#E5E7EB",
                brightBlack: "#4B5563",
                brightRed: "#FCA5A5",
                brightGreen: "#6EE7B7",
                brightYellow: "#FCD34D",
                brightBlue: "#93C5FD",
                brightMagenta: "#DDD6FE",
                brightCyan: "#67E8F9",
                brightWhite: "#F9FAFB",
                linkColor: "#38BDF8"
            )
        case .atlas:
            BuiltInTheme.makeTheme(id: id, name: "Atlas", background: "#0F172A", foreground: "#E2E8F0", accent: "#0EA5E9")
        case .ember:
            BuiltInTheme.makeTheme(id: id, name: "Ember", background: "#1C1917", foreground: "#F5F5F4", accent: "#EA580C")
        case .tide:
            BuiltInTheme.makeTheme(id: id, name: "Tide", background: "#082F49", foreground: "#E0F2FE", accent: "#06B6D4")
        case .grove:
            BuiltInTheme.makeTheme(id: id, name: "Grove", background: "#052E16", foreground: "#DCFCE7", accent: "#22C55E")
        case .brass:
            BuiltInTheme.makeTheme(id: id, name: "Brass", background: "#1F2937", foreground: "#F9FAFB", accent: "#D97706")
        case .dusk:
            BuiltInTheme.makeTheme(id: id, name: "Dusk", background: "#1E1B4B", foreground: "#EDE9FE", accent: "#818CF8")
        case .paper:
            BuiltInTheme.makeTheme(id: id, name: "Paper", background: "#F8FAFC", foreground: "#0F172A", accent: "#2563EB", light: true)
        case .signal:
            BuiltInTheme.makeTheme(id: id, name: "Signal", background: "#18181B", foreground: "#FAFAFA", accent: "#E11D48")
        case .slate:
            BuiltInTheme.makeTheme(id: id, name: "Slate", background: "#0F172A", foreground: "#CBD5E1", accent: "#64748B")
        }
    }

    private static func makeTheme(id: String, name: String, background: String, foreground: String, accent: String, light: Bool = false) -> TerminalTheme {
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
            red: "#EF4444",
            green: "#22C55E",
            yellow: "#EAB308",
            blue: "#3B82F6",
            magenta: "#A855F7",
            cyan: "#06B6D4",
            white: light ? "#E2E8F0" : "#E5E7EB",
            brightBlack: light ? "#64748B" : "#475569",
            brightRed: "#F87171",
            brightGreen: "#4ADE80",
            brightYellow: "#FACC15",
            brightBlue: "#60A5FA",
            brightMagenta: "#C084FC",
            brightCyan: "#22D3EE",
            brightWhite: light ? "#FFFFFF" : "#F8FAFC",
            linkColor: accent
        )
    }
}
