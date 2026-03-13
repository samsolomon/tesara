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
        XCTAssertTrue(store.settings.confirmOnCloseRunningSession)
        XCTAssertEqual(store.settings.tabTitleMode, .shellTitle)
        XCTAssertTrue(store.settings.dimInactiveSplits)
        XCTAssertEqual(store.settings.inactiveSplitDimAmount, 0.1, accuracy: 0.0001)
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
        XCTAssertTrue(settings.confirmOnCloseRunningSession)
        XCTAssertEqual(settings.tabTitleMode, .shellTitle)
        XCTAssertTrue(settings.dimInactiveSplits)
        XCTAssertEqual(settings.inactiveSplitDimAmount, 0.1, accuracy: 0.0001)
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
