import XCTest
@testable import Tesara

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-test-\(UUID().uuidString)")
        let suiteName = "tesara.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsStore(configDirectory: tempDir, defaults: defaults)
    }

    func testDefaultSettingsAreApplied() {
        let store = makeStore()
        XCTAssertEqual(store.settings.themeID, BuiltInTheme.oxide.id)
        XCTAssertEqual(store.settings.fontFamily, "SF Mono")
        XCTAssertEqual(store.settings.fontSize, 13)
        XCTAssertTrue(store.settings.historyCaptureEnabled)
        XCTAssertEqual(store.settings.pasteProtectionMode, .multiline)
        XCTAssertFalse(store.settings.confirmOnCloseRunningSession)
        XCTAssertEqual(store.settings.tabTitleMode, .shellTitle)
        XCTAssertTrue(store.settings.dimInactiveSplits)
        XCTAssertEqual(store.settings.inactiveSplitDimAmount, 0.3, accuracy: 0.0001)
        XCTAssertTrue(store.settings.inputBarEnabled)
        XCTAssertEqual(store.settings.cursorStyle, .bar)
        XCTAssertFalse(store.settings.autoThemeSwitching)
        XCTAssertNil(store.settings.lightThemeID)
        XCTAssertNil(store.settings.darkThemeID)
        XCTAssertEqual(store.settings.windowOpacity, 1.0)
        XCTAssertFalse(store.settings.windowBlur)
        XCTAssertEqual(store.settings.windowPaddingX, 0)
        XCTAssertEqual(store.settings.windowPaddingY, 0)
        XCTAssertTrue(store.settings.fontLigatures)
        XCTAssertFalse(store.settings.fontThicken)
        XCTAssertEqual(store.settings.optionAsAlt, .off)
        XCTAssertEqual(store.settings.scrollbackLines, 10000)
        XCTAssertFalse(store.settings.copyOnSelect)
        XCTAssertFalse(store.settings.clipboardTrimTrailingSpaces)
        XCTAssertEqual(store.settings.bellMode, .system)
    }

    func testSettingsRoundTrip() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-test-\(UUID().uuidString)")
        let suiteName = "tesara.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(configDirectory: tempDir, defaults: defaults)
        store1.settings.themeID = BuiltInTheme.atlas.id
        store1.settings.fontSize = 16
        store1.settings.historyCaptureEnabled = false
        store1.settings.pasteProtectionMode = .never
        store1.settings.confirmOnCloseRunningSession = false
        store1.settings.tabTitleMode = .workingDirectory
        store1.settings.dimInactiveSplits = false
        store1.settings.inactiveSplitDimAmount = 0.16
        store1.settings.inputBarEnabled = false
        store1.settings.cursorStyle = .block
        store1.settings.autoThemeSwitching = true
        store1.settings.lightThemeID = "light-theme"
        store1.settings.darkThemeID = "dark-theme"
        store1.settings.windowOpacity = 0.85
        store1.settings.windowBlur = true
        store1.settings.windowPaddingX = 4
        store1.settings.windowPaddingY = 2
        store1.settings.fontLigatures = false
        store1.settings.fontThicken = true
        store1.settings.optionAsAlt = .left
        store1.settings.scrollbackLines = 50000
        store1.settings.copyOnSelect = true
        store1.settings.clipboardTrimTrailingSpaces = true
        store1.settings.bellMode = .visual

        let store2 = SettingsStore(configDirectory: tempDir, defaults: defaults)
        XCTAssertEqual(store2.settings.themeID, BuiltInTheme.atlas.id)
        XCTAssertEqual(store2.settings.fontSize, 16)
        XCTAssertFalse(store2.settings.historyCaptureEnabled)
        XCTAssertEqual(store2.settings.pasteProtectionMode, .never)
        XCTAssertFalse(store2.settings.confirmOnCloseRunningSession)
        XCTAssertEqual(store2.settings.tabTitleMode, .workingDirectory)
        XCTAssertFalse(store2.settings.dimInactiveSplits)
        XCTAssertEqual(store2.settings.inactiveSplitDimAmount, 0.16, accuracy: 0.0001)
        XCTAssertFalse(store2.settings.inputBarEnabled)
        XCTAssertEqual(store2.settings.cursorStyle, .block)
        XCTAssertTrue(store2.settings.autoThemeSwitching)
        XCTAssertEqual(store2.settings.lightThemeID, "light-theme")
        XCTAssertEqual(store2.settings.darkThemeID, "dark-theme")
        XCTAssertEqual(store2.settings.windowOpacity, 0.85, accuracy: 0.0001)
        XCTAssertTrue(store2.settings.windowBlur)
        XCTAssertEqual(store2.settings.windowPaddingX, 4)
        XCTAssertEqual(store2.settings.windowPaddingY, 2)
        XCTAssertFalse(store2.settings.fontLigatures)
        XCTAssertTrue(store2.settings.fontThicken)
        XCTAssertEqual(store2.settings.optionAsAlt, .left)
        XCTAssertEqual(store2.settings.scrollbackLines, 50000)
        XCTAssertTrue(store2.settings.copyOnSelect)
        XCTAssertTrue(store2.settings.clipboardTrimTrailingSpaces)
        XCTAssertEqual(store2.settings.bellMode, .visual)
    }

    func testDecodingLegacySettingsDefaultsTrustControls() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "fontFamily": "SF Mono",
          "fontSize": 13,
          "themeID": "oxide",
          "importedThemes": [],
          "shellPath": "/bin/zsh",
          "keyBindingOverrides": [],
          "updateChecksEnabled": true,
          "localLoggingEnabled": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertTrue(settings.historyCaptureEnabled)
        XCTAssertEqual(settings.pasteProtectionMode, .multiline)
        XCTAssertFalse(settings.confirmOnCloseRunningSession)
        XCTAssertEqual(settings.tabTitleMode, .shellTitle)
        XCTAssertTrue(settings.dimInactiveSplits)
        XCTAssertEqual(settings.inactiveSplitDimAmount, 0.3, accuracy: 0.0001)
        XCTAssertTrue(settings.inputBarEnabled)
        XCTAssertEqual(settings.cursorStyle, .bar)
        XCTAssertFalse(settings.autoThemeSwitching)
        XCTAssertNil(settings.lightThemeID)
        XCTAssertNil(settings.darkThemeID)
        XCTAssertEqual(settings.windowOpacity, 1.0)
        XCTAssertFalse(settings.windowBlur)
        XCTAssertEqual(settings.windowPaddingX, 0)
        XCTAssertEqual(settings.windowPaddingY, 0)
        XCTAssertTrue(settings.fontLigatures)
        XCTAssertFalse(settings.fontThicken)
        XCTAssertEqual(settings.optionAsAlt, .off)
        XCTAssertEqual(settings.scrollbackLines, 10000)
        XCTAssertFalse(settings.copyOnSelect)
        XCTAssertFalse(settings.clipboardTrimTrailingSpaces)
        XCTAssertEqual(settings.bellMode, .system)
    }

    func testLegacyUserDefaultsMigration() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-test-\(UUID().uuidString)")
        let suiteName = "tesara.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        var legacySettings = AppSettings.default
        legacySettings.fontSize = 18
        legacySettings.themeID = BuiltInTheme.atlas.id
        let data = try! JSONEncoder().encode(legacySettings)
        defaults.set(data, forKey: "tesara.app-settings")

        let store = SettingsStore(configDirectory: tempDir, defaults: defaults)
        XCTAssertEqual(store.settings.fontSize, 18)
        XCTAssertEqual(store.settings.themeID, BuiltInTheme.atlas.id)
        XCTAssertNil(defaults.data(forKey: "tesara.app-settings"))
        XCTAssertNotNil(ConfigFile.readConfigFile(from: tempDir))
    }

    func testActiveThemeFallsBackToOxide() {
        let store = makeStore()
        store.settings.themeID = "nonexistent-theme"
        XCTAssertEqual(store.activeTheme.id, BuiltInTheme.oxide.id)
    }

    func testAvailableThemesIncludesAllBuiltIn() {
        let store = makeStore()
        XCTAssertEqual(store.availableThemes.count, BuiltInTheme.allCases.count)
    }

    func testThemeImportExportCycle() throws {
        let store = makeStore()

        let customTheme = TerminalTheme(
            id: "test-custom", name: "Test Custom",
            foreground: "#FFFFFF", background: "#000000",
            cursor: "#FF0000", cursorText: "#000000",
            selectionBackground: "#333333", selectionForeground: "#FFFFFF",
            black: "#000000", red: "#FF0000", green: "#00FF00",
            yellow: "#FFFF00", blue: "#0000FF", magenta: "#FF00FF",
            cyan: "#00FFFF", white: "#FFFFFF",
            brightBlack: "#808080", brightRed: "#FF0000",
            brightGreen: "#00FF00", brightYellow: "#FFFF00",
            brightBlue: "#0000FF", brightMagenta: "#FF00FF",
            brightCyan: "#00FFFF", brightWhite: "#FFFFFF"
        )

        try store.importTheme(from: JSONEncoder().encode(customTheme))
        XCTAssertEqual(store.settings.themeID, "test-custom")
        XCTAssertEqual(store.activeTheme.name, "Test Custom")
        XCTAssertEqual(store.availableThemes.count, BuiltInTheme.allCases.count + 1)

        let decoded = try JSONDecoder().decode(TerminalTheme.self, from: store.exportActiveTheme())
        XCTAssertEqual(decoded.id, "test-custom")

        let themes = ConfigFile.loadImportedThemes(from: store.configDirectory)
        XCTAssertEqual(themes.count, 1)
        XCTAssertEqual(themes.first?.id, "test-custom")
    }

    func testImportThemeOverwritesExisting() throws {
        let store = makeStore()

        let theme1 = TerminalTheme(
            id: "overwrite-test", name: "V1",
            foreground: "#FFFFFF", background: "#000000",
            cursor: "#FF0000", cursorText: "#000000", selectionBackground: "#333333",
            black: "#000000", red: "#FF0000", green: "#00FF00",
            yellow: "#FFFF00", blue: "#0000FF", magenta: "#FF00FF",
            cyan: "#00FFFF", white: "#FFFFFF",
            brightBlack: "#808080", brightRed: "#FF0000",
            brightGreen: "#00FF00", brightYellow: "#FFFF00",
            brightBlue: "#0000FF", brightMagenta: "#FF00FF",
            brightCyan: "#00FFFF", brightWhite: "#FFFFFF"
        )
        let theme2 = TerminalTheme(
            id: "overwrite-test", name: "V2",
            foreground: "#FFFFFF", background: "#111111",
            cursor: "#FF0000", cursorText: "#000000", selectionBackground: "#333333",
            black: "#000000", red: "#FF0000", green: "#00FF00",
            yellow: "#FFFF00", blue: "#0000FF", magenta: "#FF00FF",
            cyan: "#00FFFF", white: "#FFFFFF",
            brightBlack: "#808080", brightRed: "#FF0000",
            brightGreen: "#00FF00", brightYellow: "#FFFF00",
            brightBlue: "#0000FF", brightMagenta: "#FF00FF",
            brightCyan: "#00FFFF", brightWhite: "#FFFFFF"
        )

        try store.importTheme(from: JSONEncoder().encode(theme1))
        try store.importTheme(from: JSONEncoder().encode(theme2))
        XCTAssertEqual(store.settings.importedThemes.filter { $0.id == "overwrite-test" }.count, 1)
        XCTAssertEqual(store.activeTheme.name, "V2")
    }

    func testResetKeyBindings() {
        let store = makeStore()
        store.settings.keyBindingOverrides = [
            KeyBindingOverride(action: .copy, shortcut: KeyShortcut(key: "c", modifiers: [.command]))
        ]
        store.resetKeyBindings()
        XCTAssertTrue(store.settings.keyBindingOverrides.isEmpty)
    }

    // MARK: - Key Binding CRUD

    func testUpdateKeyBindingAddsNewOverride() {
        let store = makeStore()
        let shortcut = KeyShortcut(key: "k", modifiers: [.command, .shift])
        store.updateKeyBinding(action: .newTab, shortcut: shortcut)
        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.action, .newTab)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.shortcut, shortcut)
    }

    func testUpdateKeyBindingReplacesExisting() {
        let store = makeStore()
        store.updateKeyBinding(action: .newTab, shortcut: KeyShortcut(key: "k", modifiers: [.command]))
        store.updateKeyBinding(action: .newTab, shortcut: KeyShortcut(key: "j", modifiers: [.command]))
        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.shortcut.key, "j")
    }

    func testUpdateKeyBindingResolvesConflicts() {
        let store = makeStore()
        let shortcut = KeyShortcut(key: "k", modifiers: [.command])
        store.updateKeyBinding(action: .newTab, shortcut: shortcut)
        store.updateKeyBinding(action: .closeTab, shortcut: shortcut)
        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.action, .closeTab)
    }

    func testRemoveKeyBinding() {
        let store = makeStore()
        store.updateKeyBinding(action: .newTab, shortcut: KeyShortcut(key: "k", modifiers: [.command]))
        store.removeKeyBinding(action: .newTab)
        XCTAssertTrue(store.settings.keyBindingOverrides.isEmpty)
    }

    func testResolvedShortcutReturnsOverride() {
        let store = makeStore()
        let custom = KeyShortcut(key: "k", modifiers: [.command, .shift])
        store.updateKeyBinding(action: .newTab, shortcut: custom)
        XCTAssertEqual(store.resolvedShortcut(for: .newTab), custom)
    }

    func testResolvedShortcutFallsBackToDefault() {
        let store = makeStore()
        XCTAssertEqual(store.resolvedShortcut(for: .newTab), KeyBindingAction.newTab.defaultShortcut)
    }

    func testResolvedShortcutReturnsNilForActionWithoutDefault() {
        XCTAssertNil(makeStore().resolvedShortcut(for: .toggleTUIPassthrough))
    }

    func testResolvedShortcutWithFallbackNeverReturnsNil() {
        let fallback = KeyShortcut(key: "z", modifiers: [.command])
        XCTAssertEqual(makeStore().resolvedShortcut(for: .toggleTUIPassthrough, fallback: fallback), fallback)
    }

    // MARK: - KeyShortcut

    func testKeyShortcutDisplayValueForRegularKey() {
        XCTAssertEqual(KeyShortcut(key: "t", modifiers: [.command]).displayValue, "⌘T")
    }

    func testKeyShortcutDisplayValueForSpecialKey() {
        XCTAssertEqual(KeyShortcut(key: "\u{F700}", modifiers: [.command, .shift]).displayValue, "⌘⇧Up")
    }

    func testKeyShortcutDisplayValueMultipleModifiers() {
        XCTAssertEqual(KeyShortcut(key: "c", modifiers: [.control, .option, .shift, .command]).displayValue, "⌃⌥⇧⌘C")
    }

    func testKeyShortcutReservedDetection() {
        XCTAssertTrue(KeyShortcut(key: "q", modifiers: [.command]).isReserved)
        XCTAssertFalse(KeyShortcut(key: "t", modifiers: [.command]).isReserved)
    }

    func testKeyShortcutEquality() {
        let a = KeyShortcut(key: "t", modifiers: [.command])
        XCTAssertEqual(a, KeyShortcut(key: "t", modifiers: [.command]))
        XCTAssertNotEqual(a, KeyShortcut(key: "t", modifiers: [.command, .shift]))
    }

    func testKeyBindingOverrideRoundTrip() throws {
        let store = makeStore()
        store.updateKeyBinding(action: .closeTab, shortcut: KeyShortcut(key: "k", modifiers: [.command, .option]))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(store.settings))
        XCTAssertEqual(decoded.keyBindingOverrides.count, 1)
        XCTAssertEqual(decoded.keyBindingOverrides.first?.action, .closeTab)
        XCTAssertEqual(decoded.keyBindingOverrides.first?.shortcut.modifiers, [.command, .option])
    }

    // MARK: - LocalLogStore

    func testLocalLogStoreWritesWhenEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalLogStore(directoryURL: directory)
        store.setEnabled(true)
        store.log("test message")
        waitForLogWrite()
        let contents = try String(contentsOf: store.logFileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("test message"))
    }

    func testLocalLogStoreDoesNotWriteWhenDisabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalLogStore(directoryURL: directory)
        store.setEnabled(false)
        store.log("suppressed message")
        waitForLogWrite()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.logFileURL.path))
    }

    func testLocalLogStoreClearLogsRemovesLogDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = LocalLogStore(directoryURL: directory)
        store.setEnabled(true)
        store.log("to be cleared")
        waitForLogWrite()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.logFileURL.path))
        store.clearLogs()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func waitForLogWrite() {
        let e = XCTestExpectation(description: "log write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { e.fulfill() }
        wait(for: [e], timeout: 1)
    }
}
