import AppKit
import Foundation
import SwiftUI

struct AppSettings: Codable, Equatable {
    static let currentSchemaVersion = 7

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
    var inputBarEnabled: Bool
    var cursorStyle: CursorStyle
    var cursorBlink: Bool
    var autoThemeSwitching: Bool
    var lightThemeID: String?
    var darkThemeID: String?
    var windowOpacity: Double
    var windowBlur: Bool
    var windowPaddingX: Int
    var windowPaddingY: Int
    var fontLigatures: Bool
    var fontThicken: Bool
    var optionAsAlt: OptionAsAlt
    var scrollbackLines: Int
    var copyOnSelect: Bool
    var clipboardTrimTrailingSpaces: Bool
    var bellMode: BellMode

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
        confirmOnCloseRunningSession: Bool = false,
        tabTitleMode: TabTitleMode = .shellTitle,
        dimInactiveSplits: Bool = true,
        inactiveSplitDimAmount: Double = 0.3,
        inputBarEnabled: Bool = true,
        cursorStyle: CursorStyle = .bar,
        cursorBlink: Bool = true,
        autoThemeSwitching: Bool = false,
        lightThemeID: String? = nil,
        darkThemeID: String? = nil,
        windowOpacity: Double = 1.0,
        windowBlur: Bool = false,
        windowPaddingX: Int = 0,
        windowPaddingY: Int = 0,
        fontLigatures: Bool = true,
        fontThicken: Bool = false,
        optionAsAlt: OptionAsAlt = .off,
        scrollbackLines: Int = 10000,
        copyOnSelect: Bool = false,
        clipboardTrimTrailingSpaces: Bool = false,
        bellMode: BellMode = .system
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
        self.inputBarEnabled = inputBarEnabled
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.autoThemeSwitching = autoThemeSwitching
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.windowOpacity = windowOpacity
        self.windowBlur = windowBlur
        self.windowPaddingX = windowPaddingX
        self.windowPaddingY = windowPaddingY
        self.fontLigatures = fontLigatures
        self.fontThicken = fontThicken
        self.optionAsAlt = optionAsAlt
        self.scrollbackLines = scrollbackLines
        self.copyOnSelect = copyOnSelect
        self.clipboardTrimTrailingSpaces = clipboardTrimTrailingSpaces
        self.bellMode = bellMode
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
        case inputBarEnabled
        case cursorStyle
        case cursorBlink
        case autoThemeSwitching
        case lightThemeID
        case darkThemeID
        case windowOpacity
        case windowBlur
        case windowPaddingX
        case windowPaddingY
        case fontLigatures
        case fontThicken
        case optionAsAlt
        case scrollbackLines
        case copyOnSelect
        case clipboardTrimTrailingSpaces
        case bellMode
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
        confirmOnCloseRunningSession = try container.decodeIfPresent(Bool.self, forKey: .confirmOnCloseRunningSession) ?? false
        tabTitleMode = try container.decodeIfPresent(TabTitleMode.self, forKey: .tabTitleMode) ?? .shellTitle
        dimInactiveSplits = try container.decodeIfPresent(Bool.self, forKey: .dimInactiveSplits) ?? true
        inactiveSplitDimAmount = try container.decodeIfPresent(Double.self, forKey: .inactiveSplitDimAmount) ?? 0.3
        inputBarEnabled = try container.decodeIfPresent(Bool.self, forKey: .inputBarEnabled) ?? true
        cursorStyle = try container.decodeIfPresent(CursorStyle.self, forKey: .cursorStyle) ?? .bar
        cursorBlink = try container.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? true
        autoThemeSwitching = try container.decodeIfPresent(Bool.self, forKey: .autoThemeSwitching) ?? false
        lightThemeID = try container.decodeIfPresent(String.self, forKey: .lightThemeID)
        darkThemeID = try container.decodeIfPresent(String.self, forKey: .darkThemeID)
        windowOpacity = try container.decodeIfPresent(Double.self, forKey: .windowOpacity) ?? 1.0
        windowBlur = try container.decodeIfPresent(Bool.self, forKey: .windowBlur) ?? false
        windowPaddingX = try container.decodeIfPresent(Int.self, forKey: .windowPaddingX) ?? 0
        windowPaddingY = try container.decodeIfPresent(Int.self, forKey: .windowPaddingY) ?? 0
        fontLigatures = try container.decodeIfPresent(Bool.self, forKey: .fontLigatures) ?? true
        fontThicken = try container.decodeIfPresent(Bool.self, forKey: .fontThicken) ?? false
        optionAsAlt = try container.decodeIfPresent(OptionAsAlt.self, forKey: .optionAsAlt) ?? .off
        scrollbackLines = try container.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? 10000
        copyOnSelect = try container.decodeIfPresent(Bool.self, forKey: .copyOnSelect) ?? false
        clipboardTrimTrailingSpaces = try container.decodeIfPresent(Bool.self, forKey: .clipboardTrimTrailingSpaces) ?? false
        bellMode = try container.decodeIfPresent(BellMode.self, forKey: .bellMode) ?? .system
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

enum CursorStyle: String, Codable, CaseIterable, Identifiable {
    case bar
    case block
    case underline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar:
            "Bar"
        case .block:
            "Block"
        case .underline:
            "Underline"
        }
    }

    func editorCursorConfig(color: SIMD4<UInt8>) -> EditorLayoutEngine.CursorConfig {
        switch self {
        case .bar:
            EditorLayoutEngine.CursorConfig(
                style: self,
                barWidth: 2.5,
                rounded: true,
                color: color
            )
        case .block:
            EditorLayoutEngine.CursorConfig(
                style: self,
                barWidth: 0,
                rounded: false,
                color: color
            )
        case .underline:
            EditorLayoutEngine.CursorConfig(
                style: self,
                barWidth: 0,
                rounded: true,
                color: color
            )
        }
    }
}

enum OptionAsAlt: String, Codable, CaseIterable, Identifiable {
    case off
    case left
    case right
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .left: "Left Only"
        case .right: "Right Only"
        case .both: "Both"
        }
    }

    var ghosttyValue: String {
        switch self {
        case .off: "false"
        case .left: "left"
        case .right: "right"
        case .both: "true"
        }
    }
}

enum BellMode: String, Codable, CaseIterable, Identifiable {
    case none
    case system
    case visual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .system: "System Sound"
        case .visual: "Visual Flash"
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
    case toggleInputBar
    case toggleTUIPassthrough
    case splitRight
    case splitDown
    case closePane
    case focusNextPane
    case focusPrevPane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .newWindow: "New Window"
        case .closeTab: "Close Tab"
        case .copy: "Copy"
        case .paste: "Paste"
        case .find: "Find"
        case .openSettings: "Open Settings"
        case .toggleInputBar: "Toggle Input Editor Bar"
        case .toggleTUIPassthrough: "Toggle TUI Passthrough"
        case .splitRight: "Split Right"
        case .splitDown: "Split Down"
        case .closePane: "Close Pane"
        case .focusNextPane: "Focus Next Pane"
        case .focusPrevPane: "Focus Previous Pane"
        }
    }

    var defaultShortcut: KeyShortcut? {
        switch self {
        case .newTab: KeyShortcut(key: "t", modifiers: [.command])
        case .newWindow: nil
        case .closeTab: KeyShortcut(key: "w", modifiers: [.command, .shift])
        case .copy: KeyShortcut(key: "c", modifiers: [.command])
        case .paste: KeyShortcut(key: "v", modifiers: [.command])
        case .find: nil
        case .openSettings: KeyShortcut(key: ",", modifiers: [.command])
        case .toggleInputBar: KeyShortcut(key: "l", modifiers: [.command, .shift])
        case .toggleTUIPassthrough: nil
        case .splitRight: KeyShortcut(key: "d", modifiers: [.command])
        case .splitDown: KeyShortcut(key: "d", modifiers: [.command, .shift])
        case .closePane: KeyShortcut(key: "w", modifiers: [.command])
        case .focusNextPane: KeyShortcut(key: "]", modifiers: [.command, .option])
        case .focusPrevPane: KeyShortcut(key: "[", modifiers: [.command, .option])
        }
    }
}

struct KeyShortcut: Codable, Equatable {
    var key: String
    var modifiers: [KeyModifier]

    var displayValue: String {
        let modifierString = modifiers.map(\.symbol).joined()
        let keyDisplay = Self.specialKeyNames[key] ?? key.uppercased()
        return modifierString + keyDisplay
    }

    var eventModifierFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        for mod in modifiers {
            switch mod {
            case .command: flags.insert(.command)
            case .option: flags.insert(.option)
            case .control: flags.insert(.control)
            case .shift: flags.insert(.shift)
            }
        }
        return flags
    }

    var keyEquivalent: KeyEquivalent {
        guard let char = key.first else { return KeyEquivalent("?") }
        return KeyEquivalent(char)
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        let flags = eventModifierFlags
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    static let specialKeyNames: [String: String] = [
        "\u{1b}": "Esc", "\r": "Return", "\t": "Tab", " ": "Space",
        "\u{7f}": "Delete", "\u{F728}": "Forward Delete",
        "\u{F700}": "Up", "\u{F701}": "Down", "\u{F702}": "Left", "\u{F703}": "Right",
        "\u{F704}": "F1", "\u{F705}": "F2", "\u{F706}": "F3", "\u{F707}": "F4",
        "\u{F708}": "F5", "\u{F709}": "F6", "\u{F70A}": "F7", "\u{F70B}": "F8",
        "\u{F70C}": "F9", "\u{F70D}": "F10", "\u{F70E}": "F11", "\u{F70F}": "F12",
        "\u{F729}": "Home", "\u{F72B}": "End",
        "\u{F72C}": "Page Up", "\u{F72D}": "Page Down",
    ]

    /// System-reserved shortcuts that should not be overridden.
    static let reservedShortcuts: Set<String> = [
        "⌘Q", "⌘H", "⌘M",
    ]

    var isReserved: Bool {
        Self.reservedShortcuts.contains(displayValue)
    }

    init(key: String, modifiers: [KeyModifier]) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Require at least one non-shift modifier to avoid breaking text input
        let hasModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        guard hasModifier else { return nil }

        var mods: [KeyModifier] = []
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.shift) { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }

        self.key = chars
        self.modifiers = mods
    }
}

enum ConfigKey {
    static let fontFamily = "font-family"
    static let fontSize = "font-size"
    static let theme = "theme"
    static let fontLigatures = "font-ligatures"
    static let fontThicken = "font-thicken"
    static let cursorStyle = "cursor-style"
    static let cursorBlink = "cursor-blink"
    static let windowOpacity = "window-opacity"
    static let windowBlur = "window-blur"
    static let windowPaddingX = "window-padding-x"
    static let windowPaddingY = "window-padding-y"
    static let autoThemeSwitching = "auto-theme-switching"
    static let lightTheme = "light-theme"
    static let darkTheme = "dark-theme"
    static let shellPath = "shell-path"
    static let optionAsAlt = "option-as-alt"
    static let scrollbackLines = "scrollback-lines"
    static let copyOnSelect = "copy-on-select"
    static let clipboardTrimTrailingSpaces = "clipboard-trim-trailing-spaces"
    static let bellMode = "bell-mode"
    static let pasteProtection = "paste-protection"
    static let inputBarEnabled = "input-bar-enabled"
    static let tabTitleMode = "tab-title-mode"
    static let dimInactiveSplits = "dim-inactive-splits"
    static let inactiveSplitDimAmount = "inactive-split-dim-amount"
    static let confirmOnCloseRunningSession = "confirm-on-close-running-session"
    static let updateChecksEnabled = "update-checks-enabled"
    static let localLoggingEnabled = "local-logging-enabled"
    static let historyCaptureEnabled = "history-capture-enabled"
    static let keybind = "keybind"
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
