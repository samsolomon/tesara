import XCTest
@testable import Tesara

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeStore() -> SettingsStore {
        let suiteName = "tesara.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SettingsStore(defaults: defaults)
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
        XCTAssertEqual(store.settings.cursorBarWidth, 3.0)
        XCTAssertTrue(store.settings.cursorRounded)
        XCTAssertTrue(store.settings.cursorBlink)
        XCTAssertFalse(store.settings.cursorGlow)
        XCTAssertEqual(store.settings.cursorGlowRadius, 6.0)
        XCTAssertEqual(store.settings.cursorGlowOpacity, 0.4, accuracy: 0.001)
        XCTAssertFalse(store.settings.cursorSmoothBlink)
        // Tier 1 defaults
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
        let suiteName = "tesara.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Write
        let store1 = SettingsStore(defaults: defaults)
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
        store1.settings.cursorBarWidth = 5.0
        store1.settings.cursorRounded = false
        store1.settings.cursorBlink = false
        store1.settings.cursorGlow = true
        store1.settings.cursorGlowRadius = 10.0
        store1.settings.cursorGlowOpacity = 0.6
        store1.settings.cursorSmoothBlink = true
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

        // Read back
        let store2 = SettingsStore(defaults: defaults)
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
        XCTAssertEqual(store2.settings.cursorBarWidth, 5.0)
        XCTAssertFalse(store2.settings.cursorRounded)
        XCTAssertFalse(store2.settings.cursorBlink)
        XCTAssertTrue(store2.settings.cursorGlow)
        XCTAssertEqual(store2.settings.cursorGlowRadius, 10.0)
        XCTAssertEqual(store2.settings.cursorGlowOpacity, 0.6, accuracy: 0.001)
        XCTAssertTrue(store2.settings.cursorSmoothBlink)
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
        XCTAssertEqual(settings.cursorBarWidth, 3.0)
        XCTAssertTrue(settings.cursorRounded)
        XCTAssertTrue(settings.cursorBlink)
        XCTAssertFalse(settings.cursorGlow)
        XCTAssertEqual(settings.cursorGlowRadius, 6.0)
        XCTAssertEqual(settings.cursorGlowOpacity, 0.4, accuracy: 0.001)
        XCTAssertFalse(settings.cursorSmoothBlink)
        // Tier 1 fields default correctly from legacy JSON
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

        // Create and export a custom theme
        let customTheme = TerminalTheme(
            id: "test-custom",
            name: "Test Custom",
            foreground: "#FFFFFF",
            background: "#000000",
            cursor: "#FF0000",
            cursorText: "#000000",
            selectionBackground: "#333333",
            selectionForeground: "#FFFFFF",
            black: "#000000",
            red: "#FF0000",
            green: "#00FF00",
            yellow: "#FFFF00",
            blue: "#0000FF",
            magenta: "#FF00FF",
            cyan: "#00FFFF",
            white: "#FFFFFF",
            brightBlack: "#808080",
            brightRed: "#FF0000",
            brightGreen: "#00FF00",
            brightYellow: "#FFFF00",
            brightBlue: "#0000FF",
            brightMagenta: "#FF00FF",
            brightCyan: "#00FFFF",
            brightWhite: "#FFFFFF"
        )

        let data = try JSONEncoder().encode(customTheme)
        try store.importTheme(from: data)

        XCTAssertEqual(store.settings.themeID, "test-custom")
        XCTAssertEqual(store.activeTheme.name, "Test Custom")
        XCTAssertEqual(store.availableThemes.count, BuiltInTheme.allCases.count + 1)

        // Export and verify
        let exported = try store.exportActiveTheme()
        let decoded = try JSONDecoder().decode(TerminalTheme.self, from: exported)
        XCTAssertEqual(decoded.id, "test-custom")
        XCTAssertEqual(decoded.name, "Test Custom")
    }

    func testImportThemeOverwritesExisting() throws {
        let store = makeStore()

        let theme1 = TerminalTheme(
            id: "overwrite-test", name: "V1",
            foreground: "#FFFFFF", background: "#000000",
            cursor: "#FF0000", cursorText: "#000000",
            selectionBackground: "#333333",
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
            cursor: "#FF0000", cursorText: "#000000",
            selectionBackground: "#333333",
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

        // Should overwrite, not duplicate
        let importedCount = store.settings.importedThemes.filter { $0.id == "overwrite-test" }.count
        XCTAssertEqual(importedCount, 1)
        XCTAssertEqual(store.activeTheme.name, "V2")
    }

    func testResetKeyBindings() {
        let store = makeStore()
        store.settings.keyBindingOverrides = [
            KeyBindingOverride(action: .copy, shortcut: KeyShortcut(key: "c", modifiers: [.command]))
        ]
        XCTAssertFalse(store.settings.keyBindingOverrides.isEmpty)

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
        let original = KeyShortcut(key: "k", modifiers: [.command])
        let replacement = KeyShortcut(key: "j", modifiers: [.command])

        store.updateKeyBinding(action: .newTab, shortcut: original)
        store.updateKeyBinding(action: .newTab, shortcut: replacement)

        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.shortcut, replacement)
    }

    func testUpdateKeyBindingResolvesConflicts() {
        let store = makeStore()
        let shortcut = KeyShortcut(key: "k", modifiers: [.command])

        store.updateKeyBinding(action: .newTab, shortcut: shortcut)
        store.updateKeyBinding(action: .closeTab, shortcut: shortcut)

        // New Tab binding should be removed since Close Tab took its shortcut
        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.action, .closeTab)
    }

    func testUpdateKeyBindingAllActionsCustomizable() {
        let store = makeStore()

        store.updateKeyBinding(action: .copy, shortcut: KeyShortcut(key: "k", modifiers: [.command]))

        XCTAssertEqual(store.settings.keyBindingOverrides.count, 1)
        XCTAssertEqual(store.settings.keyBindingOverrides.first?.action, .copy)
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
        let resolved = store.resolvedShortcut(for: .newTab)

        XCTAssertEqual(resolved, KeyBindingAction.newTab.defaultShortcut)
    }

    func testResolvedShortcutReturnsNilForActionWithoutDefault() {
        let store = makeStore()
        XCTAssertNil(store.resolvedShortcut(for: .toggleTUIPassthrough))
    }

    func testResolvedShortcutWithFallbackNeverReturnsNil() {
        let store = makeStore()
        let fallback = KeyShortcut(key: "z", modifiers: [.command])
        let resolved = store.resolvedShortcut(for: .toggleTUIPassthrough, fallback: fallback)

        XCTAssertEqual(resolved, fallback)
    }

    // MARK: - KeyShortcut

    func testKeyShortcutDisplayValueForRegularKey() {
        let shortcut = KeyShortcut(key: "t", modifiers: [.command])
        XCTAssertEqual(shortcut.displayValue, "⌘T")
    }

    func testKeyShortcutDisplayValueForSpecialKey() {
        let shortcut = KeyShortcut(key: "\u{F700}", modifiers: [.command, .shift])
        XCTAssertEqual(shortcut.displayValue, "⌘⇧Up")
    }

    func testKeyShortcutDisplayValueMultipleModifiers() {
        let shortcut = KeyShortcut(key: "c", modifiers: [.control, .option, .shift, .command])
        XCTAssertEqual(shortcut.displayValue, "⌃⌥⇧⌘C")
    }

    func testKeyShortcutReservedDetection() {
        let reserved = KeyShortcut(key: "q", modifiers: [.command])
        XCTAssertTrue(reserved.isReserved)

        let notReserved = KeyShortcut(key: "t", modifiers: [.command])
        XCTAssertFalse(notReserved.isReserved)
    }

    func testKeyShortcutEquality() {
        let a = KeyShortcut(key: "t", modifiers: [.command])
        let b = KeyShortcut(key: "t", modifiers: [.command])
        let c = KeyShortcut(key: "t", modifiers: [.command, .shift])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testKeyBindingOverrideRoundTrip() throws {
        let store = makeStore()
        let shortcut = KeyShortcut(key: "k", modifiers: [.command, .option])
        store.updateKeyBinding(action: .closeTab, shortcut: shortcut)

        // Encode/decode the settings directly to verify persistence compatibility.
        let data = try JSONEncoder().encode(store.settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.keyBindingOverrides.count, 1)
        XCTAssertEqual(decoded.keyBindingOverrides.first?.action, .closeTab)
        XCTAssertEqual(decoded.keyBindingOverrides.first?.shortcut.key, "k")
        XCTAssertEqual(decoded.keyBindingOverrides.first?.shortcut.modifiers, [.command, .option])
    }

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
        let expectation = XCTestExpectation(description: "log write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}
