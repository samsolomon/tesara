import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    var settings: AppSettings = .default {
        didSet {
            guard settings != oldValue else { return }
            deferNotification()
            guard !isSuppressingPersist else { return }
            schedulePersist()
        }
    }

    @Published var previewThemeID: String?
    @Published var isDark: Bool = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    let configDirectory: URL
    private var watcher: ConfigFileWatcher?
    private var appearanceObserver: NSObjectProtocol?
    private var isSuppressingPersist = false
    private var notifyWorkItem: DispatchWorkItem?
    private var persistWorkItem: DispatchWorkItem?
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

        removeNonRemappableKeyBindings()

        watcher = ConfigFileWatcher(directory: configDirectory) { [weak self] in
            self?.reloadFromDisk()
        }

        appearanceObserver = DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    var availableThemes: [TerminalTheme] {
        BuiltInTheme.allCases.map(\.theme) + GhosttyThemeLoader.themes + settings.importedThemes.map(\.theme)
    }

    var activeTheme: TerminalTheme {
        let id: String
        if let previewThemeID {
            id = previewThemeID
        } else {
            id = switch settings.colorMode {
            case .light: settings.lightThemeID
            case .dark: settings.darkThemeID
            case .system: isDark ? settings.darkThemeID : settings.lightThemeID
            }
        }
        return availableThemes.first { $0.id == id } ?? BuiltInTheme.tesaraDark.theme
    }

    struct GhosttyConfigInputs: Equatable {
        let previewThemeID: String?
        let colorMode: ColorMode
        let lightThemeID: String
        let darkThemeID: String
        let isDark: Bool
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
            previewThemeID: previewThemeID,
            colorMode: settings.colorMode,
            lightThemeID: settings.lightThemeID,
            darkThemeID: settings.darkThemeID,
            isDark: isDark,
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
        guard action != .openSettings else { return }
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
        // Apply imported theme to the currently active slot
        switch settings.colorMode {
        case .light:
            settings.lightThemeID = imported.id
        case .dark:
            settings.darkThemeID = imported.id
        case .system:
            if isDark {
                settings.darkThemeID = imported.id
            } else {
                settings.lightThemeID = imported.id
            }
        }
    }

    func exportActiveTheme() throws -> Data {
        try JSONEncoder().encode(activeTheme)
    }


    /// Defers `objectWillChange` to the next run-loop turn so SwiftUI bindings
    /// can write without triggering "publishing during view update" warnings.
    private func deferNotification() {
        notifyWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.notifyWorkItem = nil
            self?.objectWillChange.send()
        }
        notifyWorkItem = item
        DispatchQueue.main.async(execute: item)
    }

    /// Coalesces rapid mutations into a single disk write.
    private func schedulePersist() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.persist()
        }
        persistWorkItem = item
        DispatchQueue.main.async(execute: item)
    }

    private func persist() {
        persistWorkItem = nil
        ConfigFile.writeConfigFile(content: ConfigFile.buildConfigString(from: settings), to: configDirectory)
        if let bookmark = settings.defaultWorkingDirectoryBookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
    }

    private func reloadFromDisk() {
        guard persistWorkItem == nil else { return }
        guard let content = ConfigFile.readConfigFile(from: configDirectory) else { return }
        var s = AppSettings.default
        ConfigFile.applyParsedConfig(ConfigFile.parse(content), to: &s)
        s.importedThemes = settings.importedThemes
        s.defaultWorkingDirectoryBookmark = settings.defaultWorkingDirectoryBookmark
        guard s != settings else { return }
        isSuppressingPersist = true
        settings = s
        isSuppressingPersist = false
        removeNonRemappableKeyBindings()
    }

    private func removeNonRemappableKeyBindings() {
        let filtered = settings.keyBindingOverrides.filter { $0.action != .openSettings }
        guard filtered != settings.keyBindingOverrides else { return }
        settings.keyBindingOverrides = filtered
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
