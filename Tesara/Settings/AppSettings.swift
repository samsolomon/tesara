import Foundation

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var fontFamily: String
    var fontSize: Double
    var themeID: String
    var importedThemes: [ImportedTheme]
    var shellPath: String
    var defaultWorkingDirectoryBookmark: Data?
    var keyBindingOverrides: [KeyBindingOverride]
    var updateChecksEnabled: Bool
    var localLoggingEnabled: Bool

    init(
        schemaVersion: Int = currentSchemaVersion,
        fontFamily: String = "IBM Plex Mono",
        fontSize: Double = 13,
        themeID: String = BuiltInTheme.oxide.id,
        importedThemes: [ImportedTheme] = [],
        shellPath: String = AppSettings.defaultShellPath,
        defaultWorkingDirectoryBookmark: Data? = nil,
        keyBindingOverrides: [KeyBindingOverride] = [],
        updateChecksEnabled: Bool = true,
        localLoggingEnabled: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.themeID = themeID
        self.importedThemes = importedThemes
        self.shellPath = shellPath
        self.defaultWorkingDirectoryBookmark = defaultWorkingDirectoryBookmark
        self.keyBindingOverrides = keyBindingOverrides
        self.updateChecksEnabled = updateChecksEnabled
        self.localLoggingEnabled = localLoggingEnabled
    }

    static var `default`: AppSettings {
        AppSettings()
    }

    static var defaultShellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    var defaultWorkingDirectory: URL {
        var isStale = false

        guard
            let defaultWorkingDirectoryBookmark,
            let resolvedURL = try? URL(
                resolvingBookmarkData: defaultWorkingDirectoryBookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        return resolvedURL
    }
}

struct ImportedTheme: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var theme: TerminalTheme
}

struct KeyBindingOverride: Codable, Equatable, Identifiable {
    var id: String { action.rawValue }
    var action: KeyBindingAction
    var shortcut: KeyShortcut
}

enum KeyBindingAction: String, Codable, CaseIterable, Identifiable {
    case newTab
    case newWindow
    case closeTab
    case copy
    case paste
    case find
    case openSettings
    case toggleTUIPassthrough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab:
            "New Tab"
        case .newWindow:
            "New Window"
        case .closeTab:
            "Close Tab"
        case .copy:
            "Copy"
        case .paste:
            "Paste"
        case .find:
            "Find"
        case .openSettings:
            "Open Settings"
        case .toggleTUIPassthrough:
            "Toggle TUI Passthrough"
        }
    }
}

struct KeyShortcut: Codable, Equatable {
    var key: String
    var modifiers: [KeyModifier]

    var displayValue: String {
        let modifierString = modifiers.map(\.symbol).joined()
        return modifierString + key.uppercased()
    }
}

enum KeyModifier: String, Codable, CaseIterable {
    case command
    case option
    case control
    case shift

    var symbol: String {
        switch self {
        case .command:
            "⌘"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .shift:
            "⇧"
        }
    }
}
