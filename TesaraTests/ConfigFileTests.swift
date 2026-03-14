import XCTest
@testable import Tesara

final class ConfigFileTests: XCTestCase {

    // MARK: - Parse

    func testParseSimpleKeyValue() {
        XCTAssertEqual(ConfigFile.parse("font-size = 16")["font-size"], ["16"])
    }

    func testParseSkipsCommentsAndBlanks() {
        let parsed = ConfigFile.parse("# comment\nfont-size = 16\n\n# another\n")
        XCTAssertEqual(parsed.count, 1)
    }

    func testParseRepeatableKeys() {
        let parsed = ConfigFile.parse("keybind = newTab:cmd+t\nkeybind = closeTab:cmd+shift+w\n")
        XCTAssertEqual(parsed["keybind"]?.count, 2)
    }

    func testParseValueContainingEquals() {
        let parsed = ConfigFile.parse("shell-path = /usr/bin/env VAR=1 zsh")
        XCTAssertEqual(parsed["shell-path"], ["/usr/bin/env VAR=1 zsh"])
    }

    func testParseTrimsWhitespace() {
        XCTAssertEqual(ConfigFile.parse("  font-size  =  16  ")["font-size"], ["16"])
    }

    func testParseEmptyValue() {
        XCTAssertEqual(ConfigFile.parse("light-theme =")["light-theme"], [""])
    }

    func testParseLastValueWins() {
        XCTAssertEqual(ConfigFile.parse("font-size = 13\nfont-size = 16")["font-size"]?.last, "16")
    }

    func testParseIgnoresLinesWithoutEquals() {
        XCTAssertEqual(ConfigFile.parse("font-size = 16\nbadline\ntheme = oxide").count, 2)
    }

    // MARK: - Build

    func testBuildConfigStringContainsSections() {
        let config = ConfigFile.buildConfigString(from: .default)
        for section in ["# Appearance", "# Cursor", "# Window", "# Terminal", "# Workspace", "# Privacy", "# Key bindings"] {
            XCTAssertTrue(config.contains(section), "Missing section: \(section)")
        }
    }

    func testBuildConfigStringDefaultValues() {
        let config = ConfigFile.buildConfigString(from: .default)
        XCTAssertTrue(config.contains("font-family = SF Mono"))
        XCTAssertTrue(config.contains("font-size = 13"))
        XCTAssertTrue(config.contains("cursor-style = bar"))
        XCTAssertTrue(config.contains("scrollback-lines = 10000"))
    }

    func testBuildConfigStringKeybinds() {
        var s = AppSettings.default
        s.keyBindingOverrides = [KeyBindingOverride(action: .newTab, shortcut: KeyShortcut(key: "t", modifiers: [.command]))]
        XCTAssertTrue(ConfigFile.buildConfigString(from: s).contains("keybind = newTab:cmd+t"))
    }

    // MARK: - Apply

    func testApplyBasicTypes() {
        let parsed = ConfigFile.parse("font-family = JetBrains Mono\nfont-size = 16\ncursor-blink = false\nwindow-padding-x = 4\ncursor-glow-opacity = 0.6")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontFamily, "JetBrains Mono")
        XCTAssertEqual(s.fontSize, 16)
        XCTAssertFalse(s.cursorBlink)
        XCTAssertEqual(s.windowPaddingX, 4)
        XCTAssertEqual(s.cursorGlowOpacity, 0.6, accuracy: 0.001)
    }

    func testApplyEnums() {
        let parsed = ConfigFile.parse("cursor-style = block\noption-as-alt = left\nbell-mode = visual\npaste-protection = never\ntab-title-mode = workingDirectory")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.cursorStyle, .block)
        XCTAssertEqual(s.optionAsAlt, .left)
        XCTAssertEqual(s.bellMode, .visual)
        XCTAssertEqual(s.pasteProtectionMode, .never)
        XCTAssertEqual(s.tabTitleMode, .workingDirectory)
    }

    func testApplyInvalidValuesGetDefaults() {
        let parsed = ConfigFile.parse("font-size = bad\ncursor-blink = maybe\ncursor-style = invalid\nscrollback-lines = abc")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontSize, 13)
        XCTAssertTrue(s.cursorBlink)
        XCTAssertEqual(s.cursorStyle, .bar)
        XCTAssertEqual(s.scrollbackLines, 10000)
    }

    func testApplyMissingKeysGetDefaults() {
        var s = AppSettings.default
        s.fontSize = 99
        ConfigFile.applyParsedConfig([:], to: &s)
        XCTAssertEqual(s.fontSize, 13)
    }

    func testApplyUnknownKeysIgnored() {
        let parsed = ConfigFile.parse("font-size = 16\nunknown-key = x")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontSize, 16)
    }

    func testApplyOptionalThemes() {
        let parsed = ConfigFile.parse("light-theme = my-light\ndark-theme =")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.lightThemeID, "my-light")
        XCTAssertNil(s.darkThemeID)
    }

    func testApplyKeybinds() {
        let parsed = ConfigFile.parse("keybind = newTab:cmd+t\nkeybind = closeTab:cmd+shift+w")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.keyBindingOverrides.count, 2)
        XCTAssertEqual(s.keyBindingOverrides[0].action, .newTab)
        XCTAssertEqual(s.keyBindingOverrides[1].action, .closeTab)
        XCTAssertEqual(s.keyBindingOverrides[1].shortcut.modifiers, [.command, .shift])
    }

    func testApplyNoKeybindsClearsOverrides() {
        var s = AppSettings.default
        s.keyBindingOverrides = [KeyBindingOverride(action: .copy, shortcut: KeyShortcut(key: "c", modifiers: [.command]))]
        ConfigFile.applyParsedConfig(ConfigFile.parse("font-size = 13"), to: &s)
        XCTAssertTrue(s.keyBindingOverrides.isEmpty)
    }

    func testApplyInvalidKeybindsSkipped() {
        let parsed = ConfigFile.parse("keybind = newTab:cmd+t\nkeybind = invalidAction:cmd+k\nkeybind = closeTab:badmod+w")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.keyBindingOverrides.count, 1)
    }

    // MARK: - Empty string guard (Tahoe blank-rendering regression)

    func testApplyEmptyFontFamilyFallsBackToDefault() {
        let parsed = ConfigFile.parse("font-family =")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontFamily, "SF Mono")
    }

    func testApplyEmptyShellPathFallsBackToDefault() {
        let parsed = ConfigFile.parse("shell-path =")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertFalse(s.shellPath.isEmpty)
    }

    func testApplyEmptyThemeFallsBackToDefault() {
        let parsed = ConfigFile.parse("theme =")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.themeID, BuiltInTheme.oxide.id)
    }

    // MARK: - Round Trip

    func testFullRoundTrip() {
        var original = AppSettings.default
        original.fontFamily = "JetBrains Mono"
        original.fontSize = 16
        original.themeID = "custom"
        original.fontLigatures = false
        original.fontThicken = true
        original.cursorStyle = .block
        original.cursorBarWidth = 5.0
        original.cursorRounded = false
        original.cursorBlink = false
        original.cursorGlow = true
        original.cursorGlowRadius = 10.0
        original.cursorGlowOpacity = 0.6
        original.cursorSmoothBlink = true
        original.windowOpacity = 0.85
        original.windowBlur = true
        original.windowPaddingX = 4
        original.windowPaddingY = 2
        original.autoThemeSwitching = true
        original.lightThemeID = "lt"
        original.darkThemeID = "dk"
        original.shellPath = "/usr/local/bin/fish"
        original.optionAsAlt = .left
        original.scrollbackLines = 50000
        original.copyOnSelect = true
        original.clipboardTrimTrailingSpaces = true
        original.bellMode = .visual
        original.pasteProtectionMode = .never
        original.inputBarEnabled = false
        original.tabTitleMode = .workingDirectory
        original.dimInactiveSplits = false
        original.inactiveSplitDimAmount = 0.16
        original.confirmOnCloseRunningSession = true
        original.updateChecksEnabled = false
        original.localLoggingEnabled = false
        original.historyCaptureEnabled = false
        original.keyBindingOverrides = [
            KeyBindingOverride(action: .newTab, shortcut: KeyShortcut(key: "t", modifiers: [.command, .shift])),
            KeyBindingOverride(action: .copy, shortcut: KeyShortcut(key: "c", modifiers: [.command])),
        ]

        let config = ConfigFile.buildConfigString(from: original)
        var restored = AppSettings.default
        ConfigFile.applyParsedConfig(ConfigFile.parse(config), to: &restored)

        XCTAssertEqual(restored.fontFamily, original.fontFamily)
        XCTAssertEqual(restored.fontSize, original.fontSize)
        XCTAssertEqual(restored.themeID, original.themeID)
        XCTAssertEqual(restored.fontLigatures, original.fontLigatures)
        XCTAssertEqual(restored.fontThicken, original.fontThicken)
        XCTAssertEqual(restored.cursorStyle, original.cursorStyle)
        XCTAssertEqual(restored.cursorBarWidth, original.cursorBarWidth)
        XCTAssertEqual(restored.cursorRounded, original.cursorRounded)
        XCTAssertEqual(restored.cursorBlink, original.cursorBlink)
        XCTAssertEqual(restored.cursorGlow, original.cursorGlow)
        XCTAssertEqual(restored.cursorGlowRadius, original.cursorGlowRadius)
        XCTAssertEqual(restored.cursorGlowOpacity, original.cursorGlowOpacity, accuracy: 0.001)
        XCTAssertEqual(restored.cursorSmoothBlink, original.cursorSmoothBlink)
        XCTAssertEqual(restored.windowOpacity, original.windowOpacity, accuracy: 0.001)
        XCTAssertEqual(restored.windowBlur, original.windowBlur)
        XCTAssertEqual(restored.windowPaddingX, original.windowPaddingX)
        XCTAssertEqual(restored.windowPaddingY, original.windowPaddingY)
        XCTAssertEqual(restored.autoThemeSwitching, original.autoThemeSwitching)
        XCTAssertEqual(restored.lightThemeID, original.lightThemeID)
        XCTAssertEqual(restored.darkThemeID, original.darkThemeID)
        XCTAssertEqual(restored.shellPath, original.shellPath)
        XCTAssertEqual(restored.optionAsAlt, original.optionAsAlt)
        XCTAssertEqual(restored.scrollbackLines, original.scrollbackLines)
        XCTAssertEqual(restored.copyOnSelect, original.copyOnSelect)
        XCTAssertEqual(restored.clipboardTrimTrailingSpaces, original.clipboardTrimTrailingSpaces)
        XCTAssertEqual(restored.bellMode, original.bellMode)
        XCTAssertEqual(restored.pasteProtectionMode, original.pasteProtectionMode)
        XCTAssertEqual(restored.inputBarEnabled, original.inputBarEnabled)
        XCTAssertEqual(restored.tabTitleMode, original.tabTitleMode)
        XCTAssertEqual(restored.dimInactiveSplits, original.dimInactiveSplits)
        XCTAssertEqual(restored.inactiveSplitDimAmount, original.inactiveSplitDimAmount, accuracy: 0.001)
        XCTAssertEqual(restored.confirmOnCloseRunningSession, original.confirmOnCloseRunningSession)
        XCTAssertEqual(restored.updateChecksEnabled, original.updateChecksEnabled)
        XCTAssertEqual(restored.localLoggingEnabled, original.localLoggingEnabled)
        XCTAssertEqual(restored.historyCaptureEnabled, original.historyCaptureEnabled)
        XCTAssertEqual(restored.keyBindingOverrides.count, 2)
        XCTAssertEqual(restored.keyBindingOverrides[0].action, .newTab)
        XCTAssertEqual(restored.keyBindingOverrides[1].action, .copy)
    }

    func testDefaultSettingsRoundTrip() {
        let original = AppSettings.default
        var restored = AppSettings.default
        ConfigFile.applyParsedConfig(ConfigFile.parse(ConfigFile.buildConfigString(from: original)), to: &restored)
        var expected = original
        expected.importedThemes = []
        expected.defaultWorkingDirectoryBookmark = nil
        restored.importedThemes = []
        restored.defaultWorkingDirectoryBookmark = nil
        restored.schemaVersion = expected.schemaVersion
        XCTAssertEqual(restored, expected)
    }

    // MARK: - Shortcut Serialization

    func testShortcutRoundTrips() {
        let cases: [KeyShortcut] = [
            KeyShortcut(key: "t", modifiers: [.command]),
            KeyShortcut(key: "w", modifiers: [.command, .shift]),
            KeyShortcut(key: "c", modifiers: [.control, .option, .shift, .command]),
            KeyShortcut(key: "\u{F700}", modifiers: [.command]),
            KeyShortcut(key: ",", modifiers: [.command]),
            KeyShortcut(key: "[", modifiers: [.command, .option]),
        ]
        for original in cases {
            let parsed = ConfigFile.parseShortcut(ConfigFile.serializeShortcut(original))
            XCTAssertEqual(parsed, original)
        }
    }

    func testParseShortcutAlternateNames() {
        XCTAssertEqual(ConfigFile.parseShortcut("command+t")?.modifiers, [.command])
        XCTAssertEqual(ConfigFile.parseShortcut("alt+t")?.modifiers, [.option])
        XCTAssertEqual(ConfigFile.parseShortcut("control+t")?.modifiers, [.control])
    }

    func testParseShortcutInvalidModifier() {
        XCTAssertNil(ConfigFile.parseShortcut("badmod+t"))
    }

    // MARK: - I/O

    func testReadWriteConfigFile() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-cf-\(UUID().uuidString)")
        let content = "font-size = 16\n"
        ConfigFile.writeConfigFile(content: content, to: dir)
        XCTAssertEqual(ConfigFile.readConfigFile(from: dir), content)
        try? FileManager.default.removeItem(at: dir)
    }

    func testReadMissingReturnsNil() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-cf-\(UUID().uuidString)")
        XCTAssertNil(ConfigFile.readConfigFile(from: dir))
    }

    func testSaveAndLoadThemes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-cf-\(UUID().uuidString)")
        let theme = ImportedTheme(id: "t1", name: "T1", theme: TerminalTheme(
            id: "t1", name: "T1",
            foreground: "#FFF", background: "#000", cursor: "#F00", cursorText: "#000", selectionBackground: "#333",
            black: "#000", red: "#F00", green: "#0F0", yellow: "#FF0", blue: "#00F", magenta: "#F0F", cyan: "#0FF", white: "#FFF",
            brightBlack: "#888", brightRed: "#F00", brightGreen: "#0F0", brightYellow: "#FF0",
            brightBlue: "#00F", brightMagenta: "#F0F", brightCyan: "#0FF", brightWhite: "#FFF"
        ))
        try ConfigFile.saveImportedTheme(theme, to: dir)
        let loaded = ConfigFile.loadImportedThemes(from: dir)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, "t1")
        try? FileManager.default.removeItem(at: dir)
    }
}
