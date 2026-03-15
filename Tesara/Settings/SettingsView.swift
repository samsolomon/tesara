import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct SettingsDetailView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @ObservedObject var paneSelection: SettingsPaneSelection
    let updater: SPUUpdater

    @State private var importedThemeDocument: ThemeDocument?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var isDirectoryPickerPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        SettingsDetailContainer {
            paneView(for: paneSelection.pane)
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

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .appearance:
            AppearanceSettingsPane(
                settings: $settingsStore.settings,
                themes: settingsStore.availableThemes,
                activeTheme: settingsStore.activeTheme,
                settingsStore: settingsStore,
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

enum SettingsPane: String, CaseIterable, Identifiable {
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
            "Privacy and data"
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
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private func settingRow<Content: View>(
    _ title: String,
    description: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Spacer()
        content()
    }
}

private struct AppearanceSettingsPane: View {
    @Binding var settings: AppSettings
    let themes: [TerminalTheme]
    let activeTheme: TerminalTheme
    @ObservedObject var settingsStore: SettingsStore
    let onImportTheme: () -> Void
    let onExportTheme: () -> Void

    var body: some View {
        Form {
            Section {
                settingRow("Color mode", description: "Use a fixed light or dark theme, or follow your system appearance.") {
                    Picker("", selection: $settings.colorMode) {
                        ForEach(ColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                settingRow("Light theme", description: "Used when color mode is Light, or System in light appearance.") {
                    ThemePicker(
                        selection: $settings.lightThemeID,
                        themes: themes,
                        settingsStore: settingsStore
                    )
                }

                settingRow("Dark theme", description: "Used when color mode is Dark, or System in dark appearance.") {
                    ThemePicker(
                        selection: $settings.darkThemeID,
                        themes: themes,
                        settingsStore: settingsStore
                    )
                }

                settingRow("Import and export", description: "Import a JSON theme file or export the current theme.") {
                    HStack {
                        Button("Import JSON", action: onImportTheme)
                        Button("Export current", action: onExportTheme)
                    }
                }
            } header: {
                Text("Theme")
            }

            Section {
                FixedPitchFontPicker(selection: $settings.fontFamily, previewSize: settings.fontSize)

                LabeledContent("Font size") {
                    HStack(spacing: 6) {
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                        Stepper("", value: $settings.fontSize, in: 10...24, step: 1)
                            .labelsHidden()
                    }
                }

                settingRow("Font ligatures", description: "Combines character sequences like -> into single glyphs.") {
                    Toggle("", isOn: $settings.fontLigatures)
                        .labelsHidden()
                }

                settingRow("Thicken font strokes", description: "Adds weight to thin fonts for better readability on low-DPI displays.") {
                    Toggle("", isOn: $settings.fontThicken)
                        .labelsHidden()
                }
            } header: {
                Text("Font")
            }

            Section {
                settingRow("Cursor style", description: "Choose between bar, block, or underline cursor shapes.") {
                    Picker("", selection: $settings.cursorStyle) {
                        ForEach(CursorStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                }

                settingRow("Blink cursor", description: "Animates the cursor on and off when idle.") {
                    Toggle("", isOn: $settings.cursorBlink)
                        .labelsHidden()
                }
            } header: {
                Text("Cursor")
            }

            Section {
                settingRow("Window opacity", description: "Reduces terminal window transparency for readability.") {
                    HStack(spacing: 6) {
                        Slider(value: $settings.windowOpacity, in: 0.3...1.0, step: 0.05)
                        Text("\(Int(settings.windowOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                settingRow("Background blur", description: "Applies a vibrancy effect behind translucent terminal backgrounds.") {
                    Toggle("", isOn: $settings.windowBlur)
                        .labelsHidden()
                }

                settingRow("Horizontal padding", description: "Space between the terminal content and the left and right window edges.") {
                    HStack(spacing: 6) {
                        Text("\(settings.windowPaddingX) px")
                            .monospacedDigit()
                        Stepper("", value: $settings.windowPaddingX, in: 0...50, step: 2)
                            .labelsHidden()
                    }
                }

                settingRow("Vertical padding", description: "Space between the terminal content and the top and bottom window edges.") {
                    HStack(spacing: 6) {
                        Text("\(settings.windowPaddingY) px")
                            .monospacedDigit()
                        Stepper("", value: $settings.windowPaddingY, in: 0...50, step: 2)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Window")
            }

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
                settingRow("Shell path", description: "The shell to launch in new terminal sessions.") {
                    TextField("", text: $settings.shellPath)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Default working directory") {
                    Text(settings.defaultWorkingDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button("Choose directory", action: onChooseDirectory)
            }

            Section("macOS") {
                settingRow("Option key as Alt", description: "Sends the Option key as Alt for terminal applications like vim, tmux, and emacs.") {
                    Picker("", selection: $settings.optionAsAlt) {
                        ForEach(OptionAsAlt.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
            }

            Section("Scrollback") {
                settingRow("Scrollback lines", description: "Maximum number of lines kept in the scrollback buffer.") {
                    TextField("", value: $settings.scrollbackLines, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Clipboard") {
                settingRow("Copy on select", description: "Automatically copies selected text to the clipboard.") {
                    Toggle("", isOn: $settings.copyOnSelect)
                        .labelsHidden()
                }

                settingRow("Trim trailing spaces on copy", description: "Removes trailing whitespace from copied text.") {
                    Toggle("", isOn: $settings.clipboardTrimTrailingSpaces)
                        .labelsHidden()
                }
            }

            Section("Notifications") {
                settingRow("Bell", description: "Controls how terminal bell characters are handled.") {
                    Picker("", selection: $settings.bellMode) {
                        ForEach(BellMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
            }

            Section("Safety") {
                settingRow("Paste protection", description: "Warns before pasting text that contains multiple lines.") {
                    Picker("", selection: $settings.pasteProtectionMode) {
                        ForEach(PasteProtectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                settingRow("Confirm close running session", description: "Shows a confirmation dialog before closing a tab with a running process.") {
                    Toggle("", isOn: $settings.confirmOnCloseRunningSession)
                        .labelsHidden()
                }
            }

            Section("Input") {
                settingRow("Input editor bar", description: "Shows a native text editor below the terminal and inverts terminal output to the bottom of the screen. Provides macOS text editing features like selection, undo, and emoji picker.") {
                    Toggle("", isOn: $settings.inputBarEnabled)
                        .labelsHidden()
                }
                settingRow("Show working directory", description: "Displays the current working directory and git branch above the input bar.") {
                    Toggle("", isOn: $settings.inputBarPromptInfoEnabled)
                        .labelsHidden()
                }
                .disabled(!settings.inputBarEnabled)
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
                ForEach(KeyBindingAction.customizableCases) { action in
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

            Button("Reset all to defaults") {
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
            Section("Tabs") {
                settingRow("Tab title", description: "Whether tabs display the shell-provided title or the current working directory.") {
                    Picker("", selection: $settings.tabTitleMode) {
                        ForEach(TabTitleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
            }

            Section("Splits") {
                settingRow("Dim inactive splits", description: "Reduces brightness of unfocused panes to highlight the active one.") {
                    Toggle("", isOn: $settings.dimInactiveSplits)
                        .labelsHidden()
                }

                HStack {
                    Slider(value: $settings.inactiveSplitDimAmount, in: 0.04...0.75, step: 0.01)
                        .disabled(!settings.dimInactiveSplits)

                    Text("\(Int(settings.inactiveSplitDimAmount * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(settings.dimInactiveSplits ? .secondary : .tertiary)
                        .frame(width: 40, alignment: .trailing)
                }
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
            settingRow("Check for updates automatically", description: "Periodically checks for new versions using Sparkle.") {
                Toggle("", isOn: $settings.updateChecksEnabled)
                    .labelsHidden()
            }

            CheckForUpdatesView(updater: updater)

            settingRow("Capture command history locally", description: "Stores executed commands on this Mac for the history panel.") {
                Toggle("", isOn: $settings.historyCaptureEnabled)
                    .labelsHidden()
            }

            settingRow("Enable local logging", description: "Writes diagnostic logs to disk for troubleshooting.") {
                Toggle("", isOn: $settings.localLoggingEnabled)
                    .labelsHidden()
            }

            Section {
                Button("Clear history", role: .destructive) {
                    blockStore.clearHistory()
                }

                Button("Clear local logs", role: .destructive) {
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
