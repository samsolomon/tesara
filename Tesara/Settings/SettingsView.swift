import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    let updater: SPUUpdater

    @State private var selectedPane: SettingsPane? = .appearance
    @State private var importedThemeDocument: ThemeDocument?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var isDirectoryPickerPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationTitle("Settings")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            SettingsDetailContainer(
                title: activePane.title,
                description: activePane.description
            ) {
                paneView(for: activePane)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importTheme
        )
        .fileExporter(
            isPresented: $isExporterPresented,
            document: importedThemeDocument,
            contentType: .json,
            defaultFilename: settingsStore.activeTheme.name,
            onCompletion: { _ in importedThemeDocument = nil }
        )
        .fileImporter(
            isPresented: $isDirectoryPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: selectWorkingDirectory
        )
        .alert("Theme Import Failed", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        ), actions: {
            Button("OK") {
                importErrorMessage = nil
            }
        }, message: {
            Text(importErrorMessage ?? "")
        })
    }

    private var activePane: SettingsPane {
        selectedPane ?? .appearance
    }

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .appearance:
            AppearanceSettingsPane(
                settings: $settingsStore.settings,
                themes: settingsStore.availableThemes,
                activeTheme: settingsStore.activeTheme,
                onImportTheme: { isImporterPresented = true },
                onExportTheme: exportTheme
            )
        case .terminal:
            TerminalSettingsPane(
                settings: $settingsStore.settings,
                onChooseDirectory: { isDirectoryPickerPresented = true }
            )
        case .workspace:
            WorkspaceSettingsPane(settings: $settingsStore.settings)
        case .keyboard:
            KeyboardSettingsPane()
        case .privacy:
            UpdatesPrivacySettingsPane(settings: $settingsStore.settings, updater: updater)
        }
    }

    private func importTheme(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first ?? { throw CocoaError(.fileNoSuchFile) }()
            let data = try Data(contentsOf: url)
            try settingsStore.importTheme(from: data)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func exportTheme() {
        do {
            importedThemeDocument = try ThemeDocument(data: settingsStore.exportActiveTheme())
            isExporterPresented = true
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private func selectWorkingDirectory(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }
            settingsStore.setDefaultWorkingDirectory(url)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance
    case terminal
    case workspace
    case keyboard
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance:
            "Appearance"
        case .terminal:
            "Terminal"
        case .workspace:
            "Workspace"
        case .keyboard:
            "Keyboard"
        case .privacy:
            "Privacy & Data"
        }
    }

    var description: String {
        switch self {
        case .appearance:
            "Theme, font, and visual presentation for terminal and editor panes."
        case .terminal:
            "Default shell, startup directory, and session safety controls."
        case .workspace:
            "How tabs and split panes behave throughout the workspace."
        case .keyboard:
            "Customize shortcuts for common Tesara actions."
        case .privacy:
            "Update behavior, history capture, logging, and local data controls."
        }
    }

    var systemImage: String {
        switch self {
        case .appearance:
            "paintpalette"
        case .terminal:
            "terminal"
        case .workspace:
            "square.split.2x1"
        case .keyboard:
            "keyboard"
        case .privacy:
            "lock.shield"
        }
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    let title: String
    let description: String
    let content: Content

    init(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AppearanceSettingsPane: View {
    @Binding var settings: AppSettings
    let themes: [TerminalTheme]
    let activeTheme: TerminalTheme
    let onImportTheme: () -> Void
    let onExportTheme: () -> Void

    private var themePickerOptions: some View {
        ForEach(themes) { theme in
            Text(theme.name).tag(theme.id)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.themeID) {
                    themePickerOptions
                }
                .disabled(settings.autoThemeSwitching)

                HStack {
                    Button("Import JSON", action: onImportTheme)
                    Button("Export Current", action: onExportTheme)
                }

                Toggle("Auto switch with system appearance", isOn: $settings.autoThemeSwitching)

                if settings.autoThemeSwitching {
                    Picker("Light Theme", selection: Binding(
                        get: { settings.lightThemeID ?? settings.themeID },
                        set: { settings.lightThemeID = $0 }
                    )) {
                        themePickerOptions
                    }

                    Picker("Dark Theme", selection: Binding(
                        get: { settings.darkThemeID ?? settings.themeID },
                        set: { settings.darkThemeID = $0 }
                    )) {
                        themePickerOptions
                    }
                }
            } header: {
                Text("Theme")
            }

            Section {
                TextField("Font Family", text: $settings.fontFamily)
                HStack {
                    Slider(value: $settings.fontSize, in: 10...24, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 48)
                }

                Toggle("Font ligatures", isOn: $settings.fontLigatures)
                Toggle("Thicken font strokes", isOn: $settings.fontThicken)
            } header: {
                Text("Font")
            }

            Section {
                Picker("Style", selection: $settings.cursorStyle) {
                    ForEach(CursorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                if settings.cursorStyle == .bar {
                    HStack {
                        Slider(value: $settings.cursorBarWidth, in: 1...6, step: 0.5)
                        Text("\(settings.cursorBarWidth, specifier: "%.1f") px")
                            .monospacedDigit()
                            .frame(width: 48)
                    }
                }

                if settings.cursorStyle != .underline {
                    Toggle("Rounded corners", isOn: $settings.cursorRounded)
                }

                Toggle("Cursor blink", isOn: $settings.cursorBlink)

                Toggle("Cursor glow", isOn: $settings.cursorGlow)

                if settings.cursorGlow {
                    HStack {
                        Text("Glow radius")
                        Slider(value: $settings.cursorGlowRadius, in: 2...12, step: 1)
                        Text("\(Int(settings.cursorGlowRadius)) px")
                            .monospacedDigit()
                            .frame(width: 36)
                    }

                    HStack {
                        Text("Glow opacity")
                        Slider(value: $settings.cursorGlowOpacity, in: 0.1...0.8, step: 0.05)
                        Text("\(Int(settings.cursorGlowOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }

                Toggle("Smooth cursor pulse", isOn: $settings.cursorSmoothBlink)
            } header: {
                Text("Cursor")
            } footer: {
                Text("Glow and smooth pulse apply to the editor cursor. Style and blink settings are shared with the terminal cursor.")
            }

            Section {
                HStack {
                    Slider(value: $settings.windowOpacity, in: 0.3...1.0, step: 0.05)
                    Text("\(Int(settings.windowOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 48)
                }

                Toggle("Background blur", isOn: $settings.windowBlur)

                HStack {
                    Text("Horizontal Padding")
                    Spacer()
                    TextField("", value: $settings.windowPaddingX, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("px")
                }

                HStack {
                    Text("Vertical Padding")
                    Spacer()
                    TextField("", value: $settings.windowPaddingY, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("px")
                }
            } header: {
                Text("Window")
            } footer: {
                Text("Opacity below 100% makes the terminal background translucent. Background blur applies a vibrancy effect behind the terminal.")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.headline)
                RoundedRectangle(cornerRadius: 16)
                    .fill(activeTheme.swiftUIBackgroundGradient)
                    .opacity(settings.windowOpacity)
                    .frame(height: 140)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("sam@tesara ~/src")
                                .foregroundStyle(activeTheme.swiftUIColor(from: activeTheme.green))
                            Text("$ git status")
                                .foregroundStyle(activeTheme.swiftUIColor(from: activeTheme.foreground))
                            Text("On branch main")
                                .foregroundStyle(activeTheme.swiftUIColor(from: activeTheme.cyan))
                        }
                        .font(.custom(settings.fontFamily, size: settings.fontSize))
                        .padding(16)
                    }
            }
            .padding(.top, 8)
        }
        .formStyle(.grouped)
    }
}

private struct TerminalSettingsPane: View {
    @Binding var settings: AppSettings
    let onChooseDirectory: () -> Void

    var body: some View {
        Form {
            Section("Startup") {
                TextField("Shell Path", text: $settings.shellPath)

                LabeledContent("Default Working Directory") {
                    Text(settings.defaultWorkingDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose Directory", action: onChooseDirectory)
            }

            Section {
                Picker("Option Key as Alt", selection: $settings.optionAsAlt) {
                    ForEach(OptionAsAlt.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("macOS")
            } footer: {
                Text("Sends Option key as Alt for terminal applications like vim, tmux, and emacs. \"Left Only\" keeps the right Option key for macOS character input.")
            }

            Section {
                HStack {
                    Text("Scrollback Lines")
                    Spacer()
                    TextField("", value: $settings.scrollbackLines, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("Scrollback")
            } footer: {
                Text("Maximum number of lines kept in the scrollback buffer. Higher values use more memory.")
            }

            Section {
                Toggle("Copy on select", isOn: $settings.copyOnSelect)
                Toggle("Trim trailing spaces on copy", isOn: $settings.clipboardTrimTrailingSpaces)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Copy on select automatically copies selected text to the clipboard without requiring a separate copy action.")
            }

            Section {
                Picker("Bell", selection: $settings.bellMode) {
                    ForEach(BellMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Controls how terminal bell characters (BEL) are handled. Visual flash briefly inverts the terminal colors.")
            }

            Section {
                Picker("Paste Protection", selection: $settings.pasteProtectionMode) {
                    ForEach(PasteProtectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Confirm before closing a running session", isOn: $settings.confirmOnCloseRunningSession)
            } header: {
                Text("Safety")
            } footer: {
                Text("Shell and working directory changes apply to new tabs and windows. Paste protection warns before multiline paste, and close confirmation prevents accidentally stopping a live session.")
            }

            Section {
                Toggle("Enable input editor bar", isOn: $settings.inputBarEnabled)
            } header: {
                Text("Input")
            } footer: {
                Text("Shows a native text editor at the bottom of each terminal when the shell is at a prompt. Provides full macOS text editing (selection, undo, emoji picker). Requires shell integration.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardSettingsPane: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(KeyBindingAction.allCases) { action in
                    LabeledContent(action.title) {
                        KeyRecorderView(
                            action: action,
                            currentShortcut: settingsStore.resolvedShortcut(for: action),
                            onRecord: { shortcut in
                                settingsStore.updateKeyBinding(action: action, shortcut: shortcut)
                            },
                            onClear: {
                                settingsStore.removeKeyBinding(action: action)
                            }
                        )
                    }
                }
            } footer: {
                Text("Click a shortcut to record a new key combination. Press Escape to cancel.")
            }

            Button("Reset All to Defaults") {
                settingsStore.resetKeyBindings()
            }
        }
        .formStyle(.grouped)
    }
}

private struct WorkspaceSettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Tab Title", selection: $settings.tabTitleMode) {
                    ForEach(TabTitleMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Choose whether tabs should prefer the shell-provided title or the current working directory when both are available.")
            }

            Section {
                Toggle("Dim inactive splits", isOn: $settings.dimInactiveSplits)

                HStack {
                    Slider(value: $settings.inactiveSplitDimAmount, in: 0.04...0.75, step: 0.01)
                        .disabled(!settings.dimInactiveSplits)

                    Text("\(Int(settings.inactiveSplitDimAmount * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(settings.dimInactiveSplits ? .secondary : .tertiary)
                        .frame(width: 40, alignment: .trailing)
                }
            } header: {
                Text("Splits")
            } footer: {
                Text("Inactive split dimming helps the active pane read as the current context without adding heavy borders.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesPrivacySettingsPane: View {
    @EnvironmentObject private var blockStore: BlockStore

    @Binding var settings: AppSettings
    let updater: SPUUpdater

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $settings.updateChecksEnabled)

            CheckForUpdatesView(updater: updater)

            Toggle("Capture command history locally", isOn: $settings.historyCaptureEnabled)

            Toggle("Enable local logging", isOn: $settings.localLoggingEnabled)

            Section {
                Button("Clear History", role: .destructive) {
                    blockStore.clearHistory()
                }

                Button("Clear Local Logs", role: .destructive) {
                    LocalLogStore.shared.clearLogs()
                }
            } header: {
                Text("Local Data")
            } footer: {
                Text("Turning off history capture stops new commands from being stored. Existing history remains until you clear it. Tesara writes its own local diagnostics to \(LocalLogStore.shared.displayPath) when logging is enabled.")
            }

            Section {
                Text("Tesara should make no network requests except Sparkle update checks and update downloads, and those remain user-controllable.")
                Text("Crash reporting stays disabled by default. Local logs stay on this Mac and are never uploaded.")
            } header: {
                Text("Network Policy")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
