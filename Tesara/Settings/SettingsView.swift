import Sparkle
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    let updater: SPUUpdater

    @State private var importedThemeDocument: ThemeDocument?
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var isDirectoryPickerPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        TabView {
            AppearanceSettingsPane(
                settings: $settingsStore.settings,
                themes: settingsStore.availableThemes,
                activeTheme: settingsStore.activeTheme,
                onImportTheme: { isImporterPresented = true },
                onExportTheme: exportTheme
            )
            .tabItem {
                Label("Appearance", systemImage: "paintpalette")
            }

            TerminalSettingsPane(
                settings: $settingsStore.settings,
                onChooseDirectory: { isDirectoryPickerPresented = true }
            )
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            WorkspaceSettingsPane(settings: $settingsStore.settings)
                .tabItem {
                    Label("Workspace", systemImage: "square.split.2x1")
                }

            KeyboardSettingsPane(settings: $settingsStore.settings, onReset: settingsStore.resetKeyBindings)
                .tabItem {
                    Label("Keyboard", systemImage: "keyboard")
                }

            UpdatesPrivacySettingsPane(settings: $settingsStore.settings, updater: updater)
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
        .padding(20)
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

private struct AppearanceSettingsPane: View {
    @Binding var settings: AppSettings
    let themes: [TerminalTheme]
    let activeTheme: TerminalTheme
    let onImportTheme: () -> Void
    let onExportTheme: () -> Void

    var body: some View {
        Form {
            Picker("Theme", selection: $settings.themeID) {
                ForEach(themes) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }

            HStack {
                Button("Import JSON", action: onImportTheme)
                Button("Export Current", action: onExportTheme)
            }

            TextField("Font Family", text: $settings.fontFamily)
            HStack {
                Slider(value: $settings.fontSize, in: 10...24, step: 1)
                Text("\(Int(settings.fontSize)) pt")
                    .monospacedDigit()
                    .frame(width: 48)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Preview")
                    .font(.headline)
                RoundedRectangle(cornerRadius: 16)
                    .fill(activeTheme.swiftUIBackgroundGradient)
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
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardSettingsPane: View {
    @Binding var settings: AppSettings
    let onReset: () -> Void

    var body: some View {
        Form {
            ForEach(KeyBindingAction.allCases) { action in
                LabeledContent(action.title) {
                    Text(shortcutDisplay(for: action))
                        .foregroundStyle(.secondary)
                }
            }

            Button("Reset Overrides", action: onReset)
        }
        .formStyle(.grouped)
    }

    private func shortcutDisplay(for action: KeyBindingAction) -> String {
        settings.keyBindingOverrides.first(where: { $0.action == action })?.shortcut.displayValue ?? "Default"
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
                    Slider(value: $settings.inactiveSplitDimAmount, in: 0.04...0.22, step: 0.01)
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
