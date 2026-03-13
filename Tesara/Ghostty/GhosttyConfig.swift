import Foundation

/// Maps Tesara's TerminalTheme and AppSettings into a ghostty_config_t.
///
/// Config is built by writing a config file and loading it with ghostty's
/// file-based config API. The file is persisted at a known path so that
/// hot-reload only requires overwriting and reloading.
enum GhosttyConfig {

    /// Path to the persistent ghostty config file managed by Tesara.
    static let configFilePath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Tesara", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        return appSupport.appendingPathComponent("ghostty-theme.conf").path
    }()

    /// Creates a finalized ghostty_config_t from the current theme and settings.
    /// Returns nil if config creation fails.
    static func makeConfig(theme: TerminalTheme, settings: AppSettings) -> ghostty_config_t? {
        writeConfigFile(theme: theme, settings: settings)

        let config = ghostty_config_new()
        guard config != nil else { return nil }

        configFilePath.withCString { path in
            ghostty_config_load_file(config, path)
        }
        ghostty_config_finalize(config)

        let diagCount = ghostty_config_diagnostics_count(config)
        if diagCount > 0 {
            for i in 0..<diagCount {
                let diag = ghostty_config_get_diagnostic(config, i)
                if let msg = diag.message {
                    print("[GhosttyConfig] diagnostic: \(String(cString: msg))")
                }
            }
        }

        return config
    }

    // MARK: - Config File Generation

    /// Writes the ghostty config file with current theme and settings values.
    private static func writeConfigFile(theme: TerminalTheme, settings: AppSettings) {
        var lines: [String] = []

        // Font
        lines.append("font-family = \(settings.fontFamily)")
        lines.append("font-size = \(settings.fontSize)")

        // Shell integration — disabled because Tesara provides its own
        lines.append("shell-integration = none")

        // Core colors
        lines.append("foreground = \(normalizeHex(theme.foreground))")
        lines.append("background = \(normalizeHex(theme.background))")
        lines.append("cursor-color = \(normalizeHex(theme.cursor))")
        lines.append("cursor-text = \(normalizeHex(theme.cursorText))")
        lines.append("selection-background = \(normalizeHex(theme.selectionBackground))")
        if let selFg = theme.selectionForeground {
            lines.append("selection-foreground = \(normalizeHex(selFg))")
        }

        // Standard ANSI palette (0-7)
        lines.append("palette = 0=\(normalizeHex(theme.black))")
        lines.append("palette = 1=\(normalizeHex(theme.red))")
        lines.append("palette = 2=\(normalizeHex(theme.green))")
        lines.append("palette = 3=\(normalizeHex(theme.yellow))")
        lines.append("palette = 4=\(normalizeHex(theme.blue))")
        lines.append("palette = 5=\(normalizeHex(theme.magenta))")
        lines.append("palette = 6=\(normalizeHex(theme.cyan))")
        lines.append("palette = 7=\(normalizeHex(theme.white))")

        // Bright ANSI palette (8-15)
        lines.append("palette = 8=\(normalizeHex(theme.brightBlack))")
        lines.append("palette = 9=\(normalizeHex(theme.brightRed))")
        lines.append("palette = 10=\(normalizeHex(theme.brightGreen))")
        lines.append("palette = 11=\(normalizeHex(theme.brightYellow))")
        lines.append("palette = 12=\(normalizeHex(theme.brightBlue))")
        lines.append("palette = 13=\(normalizeHex(theme.brightMagenta))")
        lines.append("palette = 14=\(normalizeHex(theme.brightCyan))")
        lines.append("palette = 15=\(normalizeHex(theme.brightWhite))")

        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(toFile: configFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("[GhosttyConfig] Failed to write config: \(error)")
        }
    }

    /// Ensures hex color has a # prefix for ghostty's config format.
    private static func normalizeHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }
}
