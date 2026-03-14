import Foundation

enum GhosttyThemeLoader {
    static let themes: [TerminalTheme] = loadThemes()

    static func parse(content: String, name: String, id: String) -> TerminalTheme? {
        var palette = [Int: String]()
        var fields = [String: String]()

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

            if key == "palette" {
                // Format: "N=#hex" or "N=hex"
                guard let eqIdx = value.firstIndex(of: "=") else { continue }
                let indexStr = value[value.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
                let color = value[value.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                if let idx = Int(indexStr) {
                    palette[idx] = normalizeHex(color)
                }
            } else {
                fields[key] = normalizeHex(value)
            }
        }

        guard let bg = fields["background"], let fg = fields["foreground"] else { return nil }

        return TerminalTheme(
            id: id,
            name: name,
            foreground: fg,
            background: bg,
            cursor: fields["cursor-color"] ?? fg,
            cursorText: fields["cursor-text"] ?? bg,
            selectionBackground: fields["selection-background"] ?? fg,
            selectionForeground: fields["selection-foreground"],
            black: palette[0] ?? "#000000",
            red: palette[1] ?? "#CC0000",
            green: palette[2] ?? "#00CC00",
            yellow: palette[3] ?? "#CCCC00",
            blue: palette[4] ?? "#0000CC",
            magenta: palette[5] ?? "#CC00CC",
            cyan: palette[6] ?? "#00CCCC",
            white: palette[7] ?? "#CCCCCC",
            brightBlack: palette[8] ?? "#555555",
            brightRed: palette[9] ?? "#FF0000",
            brightGreen: palette[10] ?? "#00FF00",
            brightYellow: palette[11] ?? "#FFFF00",
            brightBlue: palette[12] ?? "#0000FF",
            brightMagenta: palette[13] ?? "#FF00FF",
            brightCyan: palette[14] ?? "#00FFFF",
            brightWhite: palette[15] ?? "#FFFFFF"
        )
    }

    private static func normalizeHex(_ value: String) -> String {
        var hex = value
        if !hex.hasPrefix("#") {
            // Only prepend # if it looks like a hex color (6 hex chars)
            let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count == 6, UInt64(cleaned, radix: 16) != nil {
                hex = "#\(cleaned)"
            }
        }
        return hex
    }

    private static func loadThemes(from bundle: Bundle = .main) -> [TerminalTheme] {
        guard let url = bundle.resourceURL?.appendingPathComponent("GhosttyThemes") else {
            return []
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files.compactMap { fileURL in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return nil
            }
            let name = fileURL.lastPathComponent
            let id = "ghostty-\(name.lowercased())"
            return parse(content: content, name: name, id: id)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
