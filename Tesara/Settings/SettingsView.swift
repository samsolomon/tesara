import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

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

            ShellSettingsPane(
                settings: $settingsStore.settings,
                onChooseDirectory: { isDirectoryPickerPresented = true }
            )
            .tabItem {
                Label("Shell", systemImage: "terminal")
            }

            KeyboardSettingsPane(settings: $settingsStore.settings, onReset: settingsStore.resetKeyBindings)
                .tabItem {
                    Label("Keyboard", systemImage: "keyboard")
                }

            UpdatesPrivacySettingsPane(settings: $settingsStore.settings)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
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

private struct ShellSettingsPane: View {
    @Binding var settings: AppSettings
    let onChooseDirectory: () -> Void

    var body: some View {
        Form {
            TextField("Shell Path", text: $settings.shellPath)

            LabeledContent("Default Working Directory") {
                Text(settings.defaultWorkingDirectory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Button("Choose Directory", action: onChooseDirectory)

            Text("Shell and working directory changes apply to new tabs and windows.")
                .foregroundStyle(.secondary)
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

private struct UpdatesPrivacySettingsPane: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Check for updates automatically", isOn: $settings.updateChecksEnabled)
            Toggle("Enable local logging", isOn: $settings.localLoggingEnabled)

            Section {
                Text("Tesara should make no network requests except Sparkle update checks and update downloads, and those remain user-controllable.")
                Text("Crash reporting stays disabled by default. Local logs remain on this Mac in ~/Library/Logs.")
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
