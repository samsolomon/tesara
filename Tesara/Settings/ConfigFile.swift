import Foundation

enum ConfigFile {

    // MARK: - Parse

    static func parse(_ content: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key, default: []].append(value)
        }
        return result
    }

    // MARK: - Build

    static func buildConfigString(from settings: AppSettings) -> String {
        typealias K = ConfigKey
        var lines: [String] = []
        lines.append("# Tesara configuration")
        lines.append("")
        lines.append("# Appearance")
        lines.append("\(K.fontFamily) = \(settings.fontFamily)")
        lines.append("\(K.fontSize) = \(fmt(settings.fontSize))")
        lines.append("\(K.theme) = \(settings.themeID)")
        lines.append("\(K.fontLigatures) = \(settings.fontLigatures)")
        lines.append("\(K.fontThicken) = \(settings.fontThicken)")
        lines.append("")
        lines.append("# Cursor")
        lines.append("\(K.cursorStyle) = \(settings.cursorStyle.rawValue)")
        lines.append("\(K.cursorBlink) = \(settings.cursorBlink)")
        lines.append("")
        lines.append("# Window")
        lines.append("\(K.windowOpacity) = \(fmt(settings.windowOpacity))")
        lines.append("\(K.windowBlur) = \(settings.windowBlur)")
        lines.append("\(K.windowPaddingX) = \(settings.windowPaddingX)")
        lines.append("\(K.windowPaddingY) = \(settings.windowPaddingY)")
        lines.append("")
        lines.append("# Theme switching")
        lines.append("\(K.autoThemeSwitching) = \(settings.autoThemeSwitching)")
        lines.append("\(K.lightTheme) = \(settings.lightThemeID ?? "")")
        lines.append("\(K.darkTheme) = \(settings.darkThemeID ?? "")")
        lines.append("")
        lines.append("# Terminal")
        lines.append("\(K.shellPath) = \(settings.shellPath)")
        lines.append("\(K.optionAsAlt) = \(settings.optionAsAlt.rawValue)")
        lines.append("\(K.scrollbackLines) = \(settings.scrollbackLines)")
        lines.append("\(K.copyOnSelect) = \(settings.copyOnSelect)")
        lines.append("\(K.clipboardTrimTrailingSpaces) = \(settings.clipboardTrimTrailingSpaces)")
        lines.append("\(K.bellMode) = \(settings.bellMode.rawValue)")
        lines.append("\(K.pasteProtection) = \(settings.pasteProtectionMode.rawValue)")
        lines.append("\(K.inputBarEnabled) = \(settings.inputBarEnabled)")
        lines.append("")
        lines.append("# Workspace")
        lines.append("\(K.tabTitleMode) = \(settings.tabTitleMode.rawValue)")
        lines.append("\(K.dimInactiveSplits) = \(settings.dimInactiveSplits)")
        lines.append("\(K.inactiveSplitDimAmount) = \(fmt(settings.inactiveSplitDimAmount))")
        lines.append("\(K.confirmOnCloseRunningSession) = \(settings.confirmOnCloseRunningSession)")
        lines.append("")
        lines.append("# Privacy")
        lines.append("\(K.updateChecksEnabled) = \(settings.updateChecksEnabled)")
        lines.append("\(K.localLoggingEnabled) = \(settings.localLoggingEnabled)")
        lines.append("\(K.historyCaptureEnabled) = \(settings.historyCaptureEnabled)")
        lines.append("")
        lines.append("# Key bindings (action:modifiers+key)")
        for binding in settings.keyBindingOverrides {
            lines.append("\(K.keybind) = \(binding.action.rawValue):\(serializeShortcut(binding.shortcut))")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Apply

    static func applyParsedConfig(_ parsed: [String: [String]], to settings: inout AppSettings) {
        typealias K = ConfigKey
        let d = AppSettings.default

        func last(_ key: String) -> String? { parsed[key]?.last }

        /// Returns a non-empty string or nil. Guards against `font-family =` (empty value)
        /// which previously caused blank rendering (see Tahoe login fix memory).
        func nonEmpty(_ key: String) -> String? {
            guard let v = last(key), !v.isEmpty else { return nil }
            return v
        }

        func bool(_ key: String, _ def: Bool) -> Bool {
            guard let v = last(key) else { return def }
            switch v.lowercased() {
            case "true": return true
            case "false": return false
            default: return def
            }
        }

        func double(_ key: String, _ def: Double) -> Double {
            guard let v = last(key), let n = Double(v) else { return def }
            return n
        }

        func int(_ key: String, _ def: Int) -> Int {
            guard let v = last(key), let n = Int(v) else { return def }
            return n
        }

        func enumVal<E: RawRepresentable>(_ key: String, _ def: E) -> E where E.RawValue == String {
            guard let v = last(key), let e = E(rawValue: v) else { return def }
            return e
        }

        settings.fontFamily = nonEmpty(K.fontFamily) ?? d.fontFamily
        settings.fontSize = double(K.fontSize, d.fontSize)
        settings.themeID = nonEmpty(K.theme) ?? d.themeID
        settings.fontLigatures = bool(K.fontLigatures, d.fontLigatures)
        settings.fontThicken = bool(K.fontThicken, d.fontThicken)

        settings.cursorStyle = enumVal(K.cursorStyle, d.cursorStyle)
        settings.cursorBlink = bool(K.cursorBlink, d.cursorBlink)

        settings.windowOpacity = double(K.windowOpacity, d.windowOpacity)
        settings.windowBlur = bool(K.windowBlur, d.windowBlur)
        settings.windowPaddingX = int(K.windowPaddingX, d.windowPaddingX)
        settings.windowPaddingY = int(K.windowPaddingY, d.windowPaddingY)

        settings.autoThemeSwitching = bool(K.autoThemeSwitching, d.autoThemeSwitching)
        settings.lightThemeID = nonEmpty(K.lightTheme)
        settings.darkThemeID = nonEmpty(K.darkTheme)

        settings.shellPath = nonEmpty(K.shellPath) ?? d.shellPath
        settings.optionAsAlt = enumVal(K.optionAsAlt, d.optionAsAlt)
        settings.scrollbackLines = int(K.scrollbackLines, d.scrollbackLines)
        settings.copyOnSelect = bool(K.copyOnSelect, d.copyOnSelect)
        settings.clipboardTrimTrailingSpaces = bool(K.clipboardTrimTrailingSpaces, d.clipboardTrimTrailingSpaces)
        settings.bellMode = enumVal(K.bellMode, d.bellMode)
        settings.pasteProtectionMode = enumVal(K.pasteProtection, d.pasteProtectionMode)
        settings.inputBarEnabled = bool(K.inputBarEnabled, d.inputBarEnabled)

        settings.tabTitleMode = enumVal(K.tabTitleMode, d.tabTitleMode)
        settings.dimInactiveSplits = bool(K.dimInactiveSplits, d.dimInactiveSplits)
        settings.inactiveSplitDimAmount = double(K.inactiveSplitDimAmount, d.inactiveSplitDimAmount)
        settings.confirmOnCloseRunningSession = bool(K.confirmOnCloseRunningSession, d.confirmOnCloseRunningSession)

        settings.updateChecksEnabled = bool(K.updateChecksEnabled, d.updateChecksEnabled)
        settings.localLoggingEnabled = bool(K.localLoggingEnabled, d.localLoggingEnabled)
        settings.historyCaptureEnabled = bool(K.historyCaptureEnabled, d.historyCaptureEnabled)

        settings.keyBindingOverrides = (parsed[K.keybind] ?? []).compactMap { parseKeybind($0) }
    }

    // MARK: - Shortcut Serialization

    static func serializeShortcut(_ shortcut: KeyShortcut) -> String {
        var parts: [String] = []
        for mod in shortcut.modifiers {
            switch mod {
            case .command: parts.append("cmd")
            case .option: parts.append("opt")
            case .control: parts.append("ctrl")
            case .shift: parts.append("shift")
            }
        }
        parts.append(configKeyNames[shortcut.key] ?? shortcut.key)
        return parts.joined(separator: "+")
    }

    static func parseShortcut(_ string: String) -> KeyShortcut? {
        let parts = string.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var modifiers: [KeyModifier] = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "cmd", "command": modifiers.append(.command)
            case "opt", "option", "alt": modifiers.append(.option)
            case "ctrl", "control": modifiers.append(.control)
            case "shift": modifiers.append(.shift)
            default: return nil
            }
        }
        let key = reverseConfigKeyNames[parts.last!.lowercased()] ?? parts.last!
        return KeyShortcut(key: key, modifiers: modifiers)
    }

    // MARK: - I/O

    static func readConfigFile(from directory: URL) -> String? {
        try? String(contentsOf: directory.appendingPathComponent("config"), encoding: .utf8)
    }

    static func writeConfigFile(content: String, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? content.write(to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    static func loadImportedThemes(from directory: URL) -> [ImportedTheme] {
        let themesDir = directory.appendingPathComponent("themes")
        guard let files = try? FileManager.default.contentsOfDirectory(at: themesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return files.compactMap { url -> ImportedTheme? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let theme = try? decoder.decode(TerminalTheme.self, from: data) else { return nil }
            return ImportedTheme(id: theme.id, name: theme.name, theme: theme)
        }
    }

    static func saveImportedTheme(_ theme: ImportedTheme, to directory: URL) throws {
        let themesDir = directory.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(theme.theme)
        let filename = theme.id.replacingOccurrences(of: "/", with: "-") + ".json"
        try data.write(to: themesDir.appendingPathComponent(filename))
    }

    // MARK: - Private

    private static func parseKeybind(_ string: String) -> KeyBindingOverride? {
        guard let colon = string.firstIndex(of: ":") else { return nil }
        let actionStr = String(string[..<colon])
        let shortcutStr = String(string[string.index(after: colon)...])
        guard let action = KeyBindingAction(rawValue: actionStr),
              let shortcut = parseShortcut(shortcutStr) else { return nil }
        return KeyBindingOverride(action: action, shortcut: shortcut)
    }

    private static let configKeyNames: [String: String] = [
        "\u{1b}": "escape", "\r": "return", "\t": "tab", " ": "space",
        "\u{7f}": "delete", "\u{F728}": "forward_delete",
        "\u{F700}": "up", "\u{F701}": "down", "\u{F702}": "left", "\u{F703}": "right",
        "\u{F704}": "f1", "\u{F705}": "f2", "\u{F706}": "f3", "\u{F707}": "f4",
        "\u{F708}": "f5", "\u{F709}": "f6", "\u{F70A}": "f7", "\u{F70B}": "f8",
        "\u{F70C}": "f9", "\u{F70D}": "f10", "\u{F70E}": "f11", "\u{F70F}": "f12",
        "\u{F729}": "home", "\u{F72B}": "end",
        "\u{F72C}": "page_up", "\u{F72D}": "page_down",
    ]

    private static let reverseConfigKeyNames: [String: String] = {
        Dictionary(configKeyNames.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    private static func fmt(_ value: Double) -> String { String(format: "%g", value) }
}

// MARK: - File Watcher

final class ConfigFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let directory: URL
    private let callback: () -> Void

    init(directory: URL, callback: @escaping () -> Void) {
        self.directory = directory
        self.callback = callback
        watch()
    }

    deinit { source?.cancel() }

    private func watch() {
        source?.cancel()
        let fd = open(directory.appendingPathComponent("config").path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .global()
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if src.data.contains(.rename) || src.data.contains(.delete) {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.watch()
                    DispatchQueue.main.async { [weak self] in self?.callback() }
                }
            } else {
                DispatchQueue.main.async { [weak self] in self?.callback() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        self.source = src
    }
}
