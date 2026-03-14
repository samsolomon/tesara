import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageKey = "tesara.app-settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if
            let data = defaults.data(forKey: storageKey),
            let decoded = try? decoder.decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = .default
        }
    }

    var availableThemes: [TerminalTheme] {
        BuiltInTheme.allCases.map(\.theme) + settings.importedThemes.map(\.theme)
    }

    var activeTheme: TerminalTheme {
        availableThemes.first(where: { $0.id == settings.themeID }) ?? BuiltInTheme.oxide.theme
    }

    /// Combined value for observing all settings that affect ghostty config.
    /// Used by a single `.onChange` instead of three separate observers.
    struct GhosttyConfigInputs: Equatable {
        let themeID: String
        let fontFamily: String
        let fontSize: Double
    }

    var ghosttyConfigInputs: GhosttyConfigInputs {
        GhosttyConfigInputs(
            themeID: settings.themeID,
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize
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
        guard action.supportsCustomization else { return }

        // Remove any existing binding that uses this shortcut (conflict resolution)
        settings.keyBindingOverrides.removeAll { $0.action != action && $0.shortcut == shortcut }

        if let index = settings.keyBindingOverrides.firstIndex(where: { $0.action == action }) {
            settings.keyBindingOverrides[index].shortcut = shortcut
        } else {
            settings.keyBindingOverrides.append(KeyBindingOverride(action: action, shortcut: shortcut))
        }
    }

    func removeKeyBinding(action: KeyBindingAction) {
        guard action.supportsCustomization else { return }
        settings.keyBindingOverrides.removeAll { $0.action == action }
    }

    func resolvedShortcut(for action: KeyBindingAction) -> KeyShortcut? {
        settings.keyBindingOverrides.first(where: { $0.action == action })?.shortcut ?? action.defaultShortcut
    }

    func resolvedShortcut(for action: KeyBindingAction, fallback: KeyShortcut) -> KeyShortcut {
        settings.keyBindingOverrides.first(where: { $0.action == action })?.shortcut ?? action.defaultShortcut ?? fallback
    }

    func importTheme(from data: Data) throws {
        let imported = try decoder.decode(TerminalTheme.self, from: data)
        if let existingIndex = settings.importedThemes.firstIndex(where: { $0.id == imported.id }) {
            settings.importedThemes[existingIndex] = ImportedTheme(id: imported.id, name: imported.name, theme: imported)
        } else {
            settings.importedThemes.append(ImportedTheme(id: imported.id, name: imported.name, theme: imported))
        }
        settings.themeID = imported.id
    }

    func exportActiveTheme() throws -> Data {
        try encoder.encode(activeTheme)
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }
}
