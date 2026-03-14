import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard !isSuppressingPersist else { return }
            persist()
        }
    }

    let configDirectory: URL
    private var watcher: ConfigFileWatcher?
    private var isSuppressingPersist = false
    private var pendingWriteCount = 0
    private let defaults: UserDefaults
    private let legacyStorageKey = "tesara.app-settings"
    private let bookmarkKey = "tesara.defaultWorkingDirectoryBookmark"

    nonisolated static var defaultConfigDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tesara")
    }

    init(configDirectory: URL = SettingsStore.defaultConfigDirectory, defaults: UserDefaults = .standard) {
        self.configDirectory = configDirectory
        self.defaults = defaults

        if let content = ConfigFile.readConfigFile(from: configDirectory) {
            var s = AppSettings.default
            let parsed = ConfigFile.parse(content)
            ConfigFile.applyParsedConfig(parsed, to: &s)
            s.importedThemes = ConfigFile.loadImportedThemes(from: configDirectory)
            s.defaultWorkingDirectoryBookmark = defaults.data(forKey: bookmarkKey)
            settings = s
        } else if
            let data = defaults.data(forKey: legacyStorageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            isSuppressingPersist = true
            settings = decoded
            isSuppressingPersist = false
            migrateFromUserDefaults(decoded)
        } else {
            settings = .default
            persist()
        }

        watcher = ConfigFileWatcher(directory: configDirectory) { [weak self] in
            self?.reloadFromDisk()
        }
    }

    var availableThemes: [TerminalTheme] {
        BuiltInTheme.allCases.map(\.theme) + settings.importedThemes.map(\.theme)
    }

    var activeTheme: TerminalTheme {
        availableThemes.first(where: { $0.id == settings.themeID }) ?? BuiltInTheme.oxide.theme
    }

    struct GhosttyConfigInputs: Equatable {
        let themeID: String
        let fontFamily: String
        let fontSize: Double
        let cursorStyle: CursorStyle
        let cursorBlink: Bool
        let fontLigatures: Bool
        let fontThicken: Bool
        let optionAsAlt: OptionAsAlt
        let scrollbackLines: Int
        let copyOnSelect: Bool
        let clipboardTrimTrailingSpaces: Bool
        let windowOpacity: Double
        let windowPaddingX: Int
        let windowPaddingY: Int
    }

    var ghosttyConfigInputs: GhosttyConfigInputs {
        GhosttyConfigInputs(
            themeID: settings.themeID,
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize,
            cursorStyle: settings.cursorStyle,
            cursorBlink: settings.cursorBlink,
            fontLigatures: settings.fontLigatures,
            fontThicken: settings.fontThicken,
            optionAsAlt: settings.optionAsAlt,
            scrollbackLines: settings.scrollbackLines,
            copyOnSelect: settings.copyOnSelect,
            clipboardTrimTrailingSpaces: settings.clipboardTrimTrailingSpaces,
            windowOpacity: settings.windowOpacity,
            windowPaddingX: settings.windowPaddingX,
            windowPaddingY: settings.windowPaddingY
        )
    }

    struct CursorConfigInputs: Equatable {
        let cursorStyle: CursorStyle
    }

    var cursorConfigInputs: CursorConfigInputs {
        CursorConfigInputs(
            cursorStyle: settings.cursorStyle
        )
    }

    func setDefaultWorkingDirectory(_ url: URL) {
        let bookmark = try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.defaultWorkingDirectoryBookmark = bookmark
    }

    func resetKeyBindings() {
        settings.keyBindingOverrides = []
    }

    func updateKeyBinding(action: KeyBindingAction, shortcut: KeyShortcut) {
        settings.keyBindingOverrides.removeAll { $0.action != action && $0.shortcut == shortcut }
        if let index = settings.keyBindingOverrides.firstIndex(where: { $0.action == action }) {
            settings.keyBindingOverrides[index].shortcut = shortcut
        } else {
            settings.keyBindingOverrides.append(KeyBindingOverride(action: action, shortcut: shortcut))
        }
    }

    func removeKeyBinding(action: KeyBindingAction) {
        settings.keyBindingOverrides.removeAll { $0.action == action }
    }

    func resolvedShortcut(for action: KeyBindingAction) -> KeyShortcut? {
        settings.keyBindingOverrides.first(where: { $0.action == action })?.shortcut ?? action.defaultShortcut
    }

    func resolvedShortcut(for action: KeyBindingAction, fallback: KeyShortcut) -> KeyShortcut {
        settings.keyBindingOverrides.first(where: { $0.action == action })?.shortcut ?? action.defaultShortcut ?? fallback
    }

    func importTheme(from data: Data) throws {
        let imported = try JSONDecoder().decode(TerminalTheme.self, from: data)
        let importedTheme = ImportedTheme(id: imported.id, name: imported.name, theme: imported)
        try ConfigFile.saveImportedTheme(importedTheme, to: configDirectory)
        if let existingIndex = settings.importedThemes.firstIndex(where: { $0.id == imported.id }) {
            settings.importedThemes[existingIndex] = importedTheme
        } else {
            settings.importedThemes.append(importedTheme)
        }
        settings.themeID = imported.id
    }

    func exportActiveTheme() throws -> Data {
        try JSONEncoder().encode(activeTheme)
    }

    func handleAppearanceChange(isDark: Bool) {
        guard settings.autoThemeSwitching else { return }
        let newID = isDark ? settings.darkThemeID : settings.lightThemeID
        guard let newID, newID != settings.themeID else { return }
        settings.themeID = newID
    }

    private func persist() {
        pendingWriteCount += 1
        ConfigFile.writeConfigFile(content: ConfigFile.buildConfigString(from: settings), to: configDirectory)
        if let bookmark = settings.defaultWorkingDirectoryBookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pendingWriteCount -= 1
        }
    }

    private func reloadFromDisk() {
        guard pendingWriteCount == 0 else { return }
        guard let content = ConfigFile.readConfigFile(from: configDirectory) else { return }
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(ConfigFile.parse(content), to: &s)
        s.importedThemes = settings.importedThemes
        s.defaultWorkingDirectoryBookmark = settings.defaultWorkingDirectoryBookmark
        guard s != settings else { return }
        isSuppressingPersist = true
        settings = s
        isSuppressingPersist = false
    }

    private func migrateFromUserDefaults(_ decoded: AppSettings) {
        ConfigFile.writeConfigFile(content: ConfigFile.buildConfigString(from: decoded), to: configDirectory)
        for theme in decoded.importedThemes {
            try? ConfigFile.saveImportedTheme(theme, to: configDirectory)
        }
        if let bookmark = decoded.defaultWorkingDirectoryBookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
        defaults.removeObject(forKey: legacyStorageKey)
    }
}
