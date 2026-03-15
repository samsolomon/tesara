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
        let parsed = ConfigFile.parse("font-family = JetBrains Mono\nfont-size = 16\nwindow-padding-x = 4")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontFamily, "JetBrains Mono")
        XCTAssertEqual(s.fontSize, 16)
        XCTAssertEqual(s.windowPaddingX, 4)
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
        let parsed = ConfigFile.parse("font-size = bad\ncursor-style = invalid\nscrollback-lines = abc")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.fontSize, 13)
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

    func testApplyThemeOverrides() {
        let parsed = ConfigFile.parse("light-theme = my-light\ndark-theme = my-dark")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.lightThemeID, "my-light")
        XCTAssertEqual(s.darkThemeID, "my-dark")
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

    func testApplyEmptyColorModeFallsBackToDefault() {
        let parsed = ConfigFile.parse("color-mode =")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.colorMode, .system)
    }

    // MARK: - Round Trip

    func testFullRoundTrip() {
        var original = AppSettings.default
        original.fontFamily = "JetBrains Mono"
        original.fontSize = 16
        original.colorMode = .dark
        original.fontLigatures = false
        original.fontThicken = true
        original.cursorStyle = .block
        original.windowOpacity = 0.85
        original.windowBlur = true
        original.windowPaddingX = 4
        original.windowPaddingY = 2
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
        XCTAssertEqual(restored.colorMode, original.colorMode)
        XCTAssertEqual(restored.fontLigatures, original.fontLigatures)
        XCTAssertEqual(restored.fontThicken, original.fontThicken)
        XCTAssertEqual(restored.cursorStyle, original.cursorStyle)
        XCTAssertEqual(restored.windowOpacity, original.windowOpacity, accuracy: 0.001)
        XCTAssertEqual(restored.windowBlur, original.windowBlur)
        XCTAssertEqual(restored.windowPaddingX, original.windowPaddingX)
        XCTAssertEqual(restored.windowPaddingY, original.windowPaddingY)
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

    // MARK: - Legacy auto-theme-switching

    func testApplyLegacyAutoThemeSwitchingTrueSetsSystem() {
        let parsed = ConfigFile.parse("auto-theme-switching = true")
        var s = AppSettings.default
        s.colorMode = .light // start with non-system
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.colorMode, .system)
    }

    func testApplyLegacyAutoThemeSwitchingFalseKeepsDefault() {
        let parsed = ConfigFile.parse("auto-theme-switching = false")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.colorMode, AppSettings.default.colorMode)
    }

    func testApplyColorModeTakesPrecedenceOverLegacy() {
        let parsed = ConfigFile.parse("color-mode = dark\nauto-theme-switching = true")
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(parsed, to: &s)
        XCTAssertEqual(s.colorMode, .dark)
    }

    // MARK: - Windows Line Endings in Parse

    func testParseWindowsLineEndingsRequirePreNormalization() {
        // Swift treats \r\n as a single grapheme cluster, so split(separator: "\n")
        // does NOT split at \r\n boundaries. Config files with Windows line endings
        // must be pre-normalized before parsing.
        let raw = "font-size = 16\r\nshell-path = /bin/zsh\r\n"
        let rawParsed = ConfigFile.parse(raw)
        // Without normalization, the entire content is treated as a single line
        XCTAssertNil(rawParsed["shell-path"])

        // With normalization, parsing works correctly
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let parsed = ConfigFile.parse(normalized)
        XCTAssertEqual(parsed["font-size"]?.last, "16")
        XCTAssertEqual(parsed["shell-path"]?.last, "/bin/zsh")
    }

    // MARK: - Special Key Round Trips

    func testSpecialKeyShortcutRoundTrips() {
        let specialKeys: [(String, String)] = [
            ("\u{1b}", "escape"),
            ("\r", "return"),
            ("\t", "tab"),
            (" ", "space"),
            ("\u{7f}", "delete"),
            ("\u{F728}", "forward_delete"),
            ("\u{F700}", "up"),
            ("\u{F701}", "down"),
            ("\u{F702}", "left"),
            ("\u{F703}", "right"),
            ("\u{F729}", "home"),
            ("\u{F72B}", "end"),
            ("\u{F72C}", "page_up"),
            ("\u{F72D}", "page_down"),
        ]
        for (key, expectedName) in specialKeys {
            let shortcut = KeyShortcut(key: key, modifiers: [.command])
            let serialized = ConfigFile.serializeShortcut(shortcut)
            XCTAssertTrue(serialized.contains(expectedName), "Key \(key.debugDescription) should serialize to \(expectedName), got \(serialized)")
            let parsed = ConfigFile.parseShortcut(serialized)
            XCTAssertEqual(parsed, shortcut, "Round trip failed for \(expectedName)")
        }
    }

    func testParseFunctionKeyShortcuts() {
        for i in 1...12 {
            let serialized = "cmd+f\(i)"
            let parsed = ConfigFile.parseShortcut(serialized)
            XCTAssertNotNil(parsed, "Failed to parse f\(i) shortcut")
            XCTAssertEqual(parsed?.modifiers, [.command])
        }
    }

    // MARK: - Parse Empty Input

    func testParseEmptyString() {
        XCTAssertTrue(ConfigFile.parse("").isEmpty)
    }

    func testParseOnlyComments() {
        XCTAssertTrue(ConfigFile.parse("# comment 1\n# comment 2\n").isEmpty)
    }

    // MARK: - Shortcut Parse Edge Cases

    func testParseShortcutEmptyString() {
        XCTAssertNil(ConfigFile.parseShortcut(""))
    }

    func testParseShortcutKeyOnly() {
        let parsed = ConfigFile.parseShortcut("t")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.key, "t")
        XCTAssertEqual(parsed?.modifiers, [])
    }

    func testSerializeShortcutWithUnknownKey() {
        let shortcut = KeyShortcut(key: "å", modifiers: [.command])
        let serialized = ConfigFile.serializeShortcut(shortcut)
        XCTAssertEqual(serialized, "cmd+å")
    }

    // MARK: - Theme I/O Edge Cases

    func testLoadImportedThemesFromEmptyDirectory() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-themes-\(UUID().uuidString)")
        let themes = ConfigFile.loadImportedThemes(from: dir)
        XCTAssertTrue(themes.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    func testLoadImportedThemesIgnoresNonJSONFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-themes-\(UUID().uuidString)")
        let themesDir = dir.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        try "not json".write(to: themesDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let themes = ConfigFile.loadImportedThemes(from: dir)
        XCTAssertTrue(themes.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveImportedThemeSanitizesSlashesInFilename() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-themes-\(UUID().uuidString)")
        let theme = ImportedTheme(id: "custom/my-theme", name: "My Theme", theme: TerminalTheme(
            id: "custom/my-theme", name: "My Theme",
            foreground: "#FFF", background: "#000", cursor: "#F00", cursorText: "#000", selectionBackground: "#333",
            black: "#000", red: "#F00", green: "#0F0", yellow: "#FF0", blue: "#00F", magenta: "#F0F", cyan: "#0FF", white: "#FFF",
            brightBlack: "#888", brightRed: "#F00", brightGreen: "#0F0", brightYellow: "#FF0",
            brightBlue: "#00F", brightMagenta: "#F0F", brightCyan: "#0FF", brightWhite: "#FFF"
        ))
        try ConfigFile.saveImportedTheme(theme, to: dir)
        // Filename should have slash replaced with dash
        let expectedFile = dir.appendingPathComponent("themes/custom-my-theme.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path))
        try? FileManager.default.removeItem(at: dir)
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
