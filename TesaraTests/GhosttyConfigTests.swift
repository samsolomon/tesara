import XCTest
@testable import Tesara

final class GhosttyConfigTests: XCTestCase {

    private func makeTestTheme() -> TerminalTheme {
        TerminalTheme(
            id: "test-config-theme",
            name: "Test Config Theme",
            foreground: "#D4D4D4",
            background: "#1E1E1E",
            cursor: "#AEAFAD",
            cursorText: "#000000",
            selectionBackground: "#264F78",
            selectionForeground: "#FFFFFF",
            black: "#000000",
            red: "#CD3131",
            green: "#0DBC79",
            yellow: "#E5E510",
            blue: "#2472C8",
            magenta: "#BC3FBC",
            cyan: "#11A8CD",
            white: "#E5E5E5",
            brightBlack: "#666666",
            brightRed: "#F14C4C",
            brightGreen: "#23D18B",
            brightYellow: "#F5F543",
            brightBlue: "#3B8EEA",
            brightMagenta: "#D670D6",
            brightCyan: "#29B8DB",
            brightWhite: "#FFFFFF"
        )
    }

    private func makeTestSettings(fontFamily: String = "Menlo", fontSize: Double = 13.0) -> AppSettings {
        AppSettings(fontFamily: fontFamily, fontSize: fontSize)
    }

    // MARK: - buildConfigString (pure, no file I/O)

    func testConfigStringContainsFontSettings() {
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: makeTestSettings(fontFamily: "JetBrains Mono", fontSize: 14.0)
        )
        XCTAssertTrue(content.contains("font-family = JetBrains Mono"))
        XCTAssertTrue(content.contains("font-size = 14.0"))
    }

    func testConfigStringDisablesShellIntegration() {
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: makeTestSettings()
        )
        XCTAssertTrue(content.contains("shell-integration = none"))
    }

    func testConfigStringContainsCoreColors() {
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: makeTestSettings()
        )
        XCTAssertTrue(content.contains("foreground = #D4D4D4"))
        XCTAssertTrue(content.contains("background = #1E1E1E"))
        XCTAssertTrue(content.contains("cursor-color = #AEAFAD"))
        XCTAssertTrue(content.contains("cursor-text = #000000"))
        XCTAssertTrue(content.contains("selection-background = #264F78"))
        XCTAssertTrue(content.contains("selection-foreground = #FFFFFF"))
    }

    func testConfigStringContainsAllPaletteColors() {
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: makeTestSettings()
        )

        // Standard palette
        XCTAssertTrue(content.contains("palette = 0=#000000"))
        XCTAssertTrue(content.contains("palette = 1=#CD3131"))
        XCTAssertTrue(content.contains("palette = 2=#0DBC79"))
        XCTAssertTrue(content.contains("palette = 3=#E5E510"))
        XCTAssertTrue(content.contains("palette = 4=#2472C8"))
        XCTAssertTrue(content.contains("palette = 5=#BC3FBC"))
        XCTAssertTrue(content.contains("palette = 6=#11A8CD"))
        XCTAssertTrue(content.contains("palette = 7=#E5E5E5"))

        // Bright palette
        XCTAssertTrue(content.contains("palette = 8=#666666"))
        XCTAssertTrue(content.contains("palette = 9=#F14C4C"))
        XCTAssertTrue(content.contains("palette = 10=#23D18B"))
        XCTAssertTrue(content.contains("palette = 11=#F5F543"))
        XCTAssertTrue(content.contains("palette = 12=#3B8EEA"))
        XCTAssertTrue(content.contains("palette = 13=#D670D6"))
        XCTAssertTrue(content.contains("palette = 14=#29B8DB"))
        XCTAssertTrue(content.contains("palette = 15=#FFFFFF"))
    }

    func testConfigStringOmitsSelectionForegroundWhenNil() {
        let theme = makeTestTheme()
        let themeWithoutSelFg = TerminalTheme(
            id: theme.id, name: theme.name,
            foreground: theme.foreground, background: theme.background,
            cursor: theme.cursor, cursorText: theme.cursorText,
            selectionBackground: theme.selectionBackground,
            selectionForeground: nil,
            black: theme.black, red: theme.red, green: theme.green,
            yellow: theme.yellow, blue: theme.blue, magenta: theme.magenta,
            cyan: theme.cyan, white: theme.white,
            brightBlack: theme.brightBlack, brightRed: theme.brightRed,
            brightGreen: theme.brightGreen, brightYellow: theme.brightYellow,
            brightBlue: theme.brightBlue, brightMagenta: theme.brightMagenta,
            brightCyan: theme.brightCyan, brightWhite: theme.brightWhite
        )

        let content = GhosttyConfig.buildConfigString(
            theme: themeWithoutSelFg,
            settings: makeTestSettings()
        )
        XCTAssertFalse(content.contains("selection-foreground"))
    }

    // MARK: - Hex Normalization

    func testColorsWithoutHashGetNormalized() {
        let theme = TerminalTheme(
            id: "no-hash", name: "No Hash",
            foreground: "AABBCC", background: "112233",
            cursor: "FFFFFF", cursorText: "000000",
            selectionBackground: "445566",
            black: "000000", red: "FF0000", green: "00FF00",
            yellow: "FFFF00", blue: "0000FF", magenta: "FF00FF",
            cyan: "00FFFF", white: "FFFFFF",
            brightBlack: "808080", brightRed: "FF8080",
            brightGreen: "80FF80", brightYellow: "FFFF80",
            brightBlue: "8080FF", brightMagenta: "FF80FF",
            brightCyan: "80FFFF", brightWhite: "FFFFFF"
        )

        let content = GhosttyConfig.buildConfigString(
            theme: theme,
            settings: makeTestSettings()
        )
        XCTAssertTrue(content.contains("foreground = #AABBCC"))
        XCTAssertTrue(content.contains("background = #112233"))
    }

    // MARK: - Config Sanitization

    func testFontFamilyWithNewlineIsStripped() {
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: makeTestSettings(fontFamily: "Menlo\ncommand = /bin/evil")
        )
        // Newline should be stripped — no extra config line injected
        XCTAssertTrue(content.contains("font-family = Menlocommand = /bin/evil"))
        // The injected directive should NOT appear as a separate config line
        let lines = content.components(separatedBy: "\n")
        XCTAssertFalse(lines.contains("command = /bin/evil"))
    }

    func testHexColorWithNewlineIsStripped() {
        let theme = TerminalTheme(
            id: "inject", name: "Inject",
            foreground: "#AABB\ncommand = /bin/evil", background: "#112233",
            cursor: "#FFFFFF", cursorText: "#000000",
            selectionBackground: "#445566",
            black: "#000000", red: "#FF0000", green: "#00FF00",
            yellow: "#FFFF00", blue: "#0000FF", magenta: "#FF00FF",
            cyan: "#00FFFF", white: "#FFFFFF",
            brightBlack: "#808080", brightRed: "#FF8080",
            brightGreen: "#80FF80", brightYellow: "#FFFF80",
            brightBlue: "#8080FF", brightMagenta: "#FF80FF",
            brightCyan: "#80FFFF", brightWhite: "#FFFFFF"
        )

        let content = GhosttyConfig.buildConfigString(
            theme: theme,
            settings: makeTestSettings()
        )
        let lines = content.components(separatedBy: "\n")
        XCTAssertFalse(lines.contains("command = /bin/evil"))
    }

    // MARK: - Cursor Config

    func testConfigStringContainsCursorStyleBar() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("cursor-style = bar"))
        XCTAssertTrue(content.contains("cursor-style-blink = true"))
    }

    func testConfigStringContainsCursorStyleBlock() {
        var settings = makeTestSettings()
        settings.cursorStyle = .block
        settings.cursorBlink = false
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("cursor-style = block"))
        XCTAssertTrue(content.contains("cursor-style-blink = false"))
    }

    func testConfigStringContainsCursorStyleUnderline() {
        var settings = makeTestSettings()
        settings.cursorStyle = .underline
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("cursor-style = underline"))
    }

    func testConfigStringContainsCursorOpacityWhenGlowEnabled() {
        var settings = makeTestSettings()
        settings.cursorGlow = true
        settings.cursorGlowOpacity = 0.4
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("cursor-opacity = "))
    }

    func testConfigStringOmitsCursorOpacityWhenGlowDisabled() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertFalse(content.contains("cursor-opacity"))
    }

    // MARK: - Tier 1 Settings

    func testConfigStringContainsOptionAsAlt() {
        var settings = makeTestSettings()
        settings.optionAsAlt = .left
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("macos-option-as-alt = left"))
    }

    func testConfigStringContainsOptionAsAltBoth() {
        var settings = makeTestSettings()
        settings.optionAsAlt = .both
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("macos-option-as-alt = true"))
    }

    func testConfigStringContainsOptionAsAltOff() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("macos-option-as-alt = false"))
    }

    func testConfigStringContainsScrollbackLimit() {
        var settings = makeTestSettings()
        settings.scrollbackLines = 50000
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("scrollback-limit = 50000"))
    }

    func testConfigStringContainsDefaultScrollback() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("scrollback-limit = 10000"))
    }

    func testConfigStringContainsCopyOnSelect() {
        var settings = makeTestSettings()
        settings.copyOnSelect = true
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("copy-on-select = clipboard"))
    }

    func testConfigStringOmitsCopyOnSelectWhenDisabled() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertFalse(content.contains("copy-on-select"))
    }

    func testConfigStringContainsClipboardTrim() {
        var settings = makeTestSettings()
        settings.clipboardTrimTrailingSpaces = true
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("clipboard-trim-trailing-spaces = true"))
    }

    func testConfigStringContainsFontThicken() {
        var settings = makeTestSettings()
        settings.fontThicken = true
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("font-thicken = true"))
    }

    func testConfigStringDisablesLigatures() {
        var settings = makeTestSettings()
        settings.fontLigatures = false
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("font-feature = -liga"))
        XCTAssertTrue(content.contains("font-feature = -clig"))
    }

    func testConfigStringOmitsLigatureDisableByDefault() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertFalse(content.contains("font-feature"))
    }

    func testConfigStringContainsWindowOpacity() {
        var settings = makeTestSettings()
        settings.windowOpacity = 0.85
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("background-opacity = 0.85"))
    }

    func testConfigStringOmitsFullOpacity() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertFalse(content.contains("background-opacity"))
    }

    func testConfigStringContainsWindowPadding() {
        var settings = makeTestSettings()
        settings.windowPaddingX = 8
        settings.windowPaddingY = 4
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertTrue(content.contains("window-padding-x = 8"))
        XCTAssertTrue(content.contains("window-padding-y = 4"))
    }

    func testConfigStringOmitsZeroPadding() {
        let settings = makeTestSettings()
        let content = GhosttyConfig.buildConfigString(
            theme: makeTestTheme(),
            settings: settings
        )
        XCTAssertFalse(content.contains("window-padding-x"))
        XCTAssertFalse(content.contains("window-padding-y"))
    }

    // MARK: - Config File Overwrite (requires file I/O)

    func testMakeConfigOverwritesPreviousFile() {
        let theme1 = makeTestTheme()
        let settings1 = makeTestSettings(fontFamily: "Menlo", fontSize: 12.0)
        GhosttyConfig.writeConfigFile(theme: theme1, settings: settings1)

        let settings2 = makeTestSettings(fontFamily: "Fira Code", fontSize: 16.0)
        GhosttyConfig.writeConfigFile(theme: theme1, settings: settings2)

        let content = try? String(contentsOfFile: GhosttyConfig.configFilePath, encoding: .utf8)
        XCTAssertTrue(content?.contains("font-family = Fira Code") ?? false)
        XCTAssertTrue(content?.contains("font-size = 16.0") ?? false)
        XCTAssertFalse(content?.contains("font-family = Menlo") ?? true)
    }
}
