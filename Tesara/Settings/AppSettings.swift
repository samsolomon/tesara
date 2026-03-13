import Foundation

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 4

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
    var historyCaptureEnabled: Bool
    var pasteProtectionMode: PasteProtectionMode
    var confirmOnCloseRunningSession: Bool
    var tabTitleMode: TabTitleMode
    var dimInactiveSplits: Bool
    var inactiveSplitDimAmount: Double

    init(
        schemaVersion: Int = currentSchemaVersion,
        fontFamily: String = "SF Mono",
        fontSize: Double = 13,
        themeID: String = BuiltInTheme.oxide.id,
        importedThemes: [ImportedTheme] = [],
        shellPath: String = AppSettings.defaultShellPath,
        defaultWorkingDirectoryBookmark: Data? = nil,
        keyBindingOverrides: [KeyBindingOverride] = [],
        updateChecksEnabled: Bool = true,
        localLoggingEnabled: Bool = true,
        historyCaptureEnabled: Bool = true,
        pasteProtectionMode: PasteProtectionMode = .multiline,
        confirmOnCloseRunningSession: Bool = true,
        tabTitleMode: TabTitleMode = .shellTitle,
        dimInactiveSplits: Bool = true,
        inactiveSplitDimAmount: Double = 0.1
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
        self.historyCaptureEnabled = historyCaptureEnabled
        self.pasteProtectionMode = pasteProtectionMode
        self.confirmOnCloseRunningSession = confirmOnCloseRunningSession
        self.tabTitleMode = tabTitleMode
        self.dimInactiveSplits = dimInactiveSplits
        self.inactiveSplitDimAmount = inactiveSplitDimAmount
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case fontFamily
        case fontSize
        case themeID
        case importedThemes
        case shellPath
        case defaultWorkingDirectoryBookmark
        case keyBindingOverrides
        case updateChecksEnabled
        case localLoggingEnabled
        case historyCaptureEnabled
        case pasteProtectionMode
        case confirmOnCloseRunningSession
        case tabTitleMode
        case dimInactiveSplits
        case inactiveSplitDimAmount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "SF Mono"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        themeID = try container.decodeIfPresent(String.self, forKey: .themeID) ?? BuiltInTheme.oxide.id
        importedThemes = try container.decodeIfPresent([ImportedTheme].self, forKey: .importedThemes) ?? []
        shellPath = try container.decodeIfPresent(String.self, forKey: .shellPath) ?? AppSettings.defaultShellPath
        defaultWorkingDirectoryBookmark = try container.decodeIfPresent(Data.self, forKey: .defaultWorkingDirectoryBookmark)
        keyBindingOverrides = try container.decodeIfPresent([KeyBindingOverride].self, forKey: .keyBindingOverrides) ?? []
        updateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .updateChecksEnabled) ?? true
        localLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .localLoggingEnabled) ?? true
        historyCaptureEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyCaptureEnabled) ?? true
        pasteProtectionMode = try container.decodeIfPresent(PasteProtectionMode.self, forKey: .pasteProtectionMode) ?? .multiline
        confirmOnCloseRunningSession = try container.decodeIfPresent(Bool.self, forKey: .confirmOnCloseRunningSession) ?? true
        tabTitleMode = try container.decodeIfPresent(TabTitleMode.self, forKey: .tabTitleMode) ?? .shellTitle
        dimInactiveSplits = try container.decodeIfPresent(Bool.self, forKey: .dimInactiveSplits) ?? true
        inactiveSplitDimAmount = try container.decodeIfPresent(Double.self, forKey: .inactiveSplitDimAmount) ?? 0.1
    }
}

enum PasteProtectionMode: String, Codable, CaseIterable, Identifiable {
    case never
    case multiline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never:
            "Never"
        case .multiline:
            "Confirm Multiline Paste"
        }
    }
}

enum TabTitleMode: String, Codable, CaseIterable, Identifiable {
    case shellTitle
    case workingDirectory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shellTitle:
            "Prefer Shell Title"
        case .workingDirectory:
            "Prefer Working Directory"
        }
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
