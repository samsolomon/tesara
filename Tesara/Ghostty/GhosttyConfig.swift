import Foundation

/// Maps Tesara's TerminalTheme and AppSettings into a ghostty_config_t.
///
/// Config is built by writing a config file and loading it with ghostty's
/// file-based config API. The file is persisted at a known path so that
/// hot-reload only requires overwriting and reloading.
enum GhosttyConfig {

    /// Path to the persistent ghostty config file managed by Tesara.
    static let configFilePath: String = {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            // Fallback to temp directory if Application Support is unavailable
            return NSTemporaryDirectory() + "tesara-ghostty-theme.conf"
        }
        let appSupport = baseURL.appendingPathComponent("Tesara", isDirectory: true)

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
                    LocalLogStore.shared.log("[GhosttyConfig] diagnostic: \(String(cString: msg))")
                }
            }
        }

        return config
    }

    // MARK: - Config File Generation

    /// Writes the ghostty config file with current theme and settings values.
    /// Internal (not private) so tests can call this without requiring ghostty library init.
    static func writeConfigFile(theme: TerminalTheme, settings: AppSettings) {
        let content = buildConfigString(theme: theme, settings: settings)
        do {
            try content.write(toFile: configFilePath, atomically: true, encoding: .utf8)
        } catch {
            LocalLogStore.shared.log("[GhosttyConfig] Failed to write config: \(error)")
        }
    }

    /// Pure function that builds the ghostty config file content string.
    /// Separated from file I/O for testability.
    static func buildConfigString(theme: TerminalTheme, settings: AppSettings) -> String {
        var lines: [String] = []

        // Font — sanitize to prevent config injection via newlines
        let fontFamily = settings.fontFamily.isEmpty ? "SF Mono" : settings.fontFamily
        lines.append("font-family = \(sanitize(fontFamily))")
        lines.append("font-size = \(settings.fontSize)")

        // Shell integration — disabled because Tesara provides its own
        lines.append("shell-integration = none")


        // Font options
        if !settings.fontLigatures {
            lines.append("font-feature = -liga")
            lines.append("font-feature = -clig")
        }
        lines.append("font-thicken = \(settings.fontThicken)")

        // Cursor
        lines.append("cursor-style = \(settings.cursorStyle.rawValue)")
        lines.append("cursor-style-blink = \(settings.cursorBlink)")

        // Window
        lines.append("background-opacity = \(settings.windowOpacity)")
        lines.append("window-padding-x = \(settings.windowPaddingX)")
        lines.append("window-padding-y = \(settings.windowPaddingY)")

        // macOS
        lines.append("macos-option-as-alt = \(settings.optionAsAlt.ghosttyValue)")

        // Scrollback
        lines.append("scrollback-limit = \(settings.scrollbackLines)")

        // Clipboard
        if settings.copyOnSelect {
            lines.append("copy-on-select = clipboard")
        }
        lines.append("clipboard-trim-trailing-spaces = \(settings.clipboardTrimTrailingSpaces)")

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

        return lines.joined(separator: "\n") + "\n"
    }

    /// Sanitizes a config value by removing newlines and carriage returns
    /// to prevent injection of additional config directives.
    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "")
             .replacingOccurrences(of: "\r", with: "")
    }

    /// Ensures hex color has a # prefix for ghostty's config format.
    private static func normalizeHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = sanitize(trimmed)
        return sanitized.hasPrefix("#") ? sanitized : "#\(sanitized)"
    }
}
