import Sparkle
import SwiftUI

struct TesaraAppCommands: Commands {
    @ObservedObject var manager: WorkspaceManager
    @ObservedObject var settingsStore: SettingsStore
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                SettingsWindowController.shared.showWindow(nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                manager.newTabFromDefaults()
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .newTab, fallback: KeyShortcut(key: "t", modifiers: [.command])))

            Button("Close Pane") {
                if let id = manager.activePaneID {
                    manager.closePane(id: id)
                }
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .closePane, fallback: KeyShortcut(key: "w", modifiers: [.command])))

            Button("Close Tab") {
                if let id = manager.activeTabID {
                    manager.closeTab(id: id)
                }
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .closeTab, fallback: KeyShortcut(key: "w", modifiers: [.command, .shift])))
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                manager.saveActiveEditor()
            }
            .keyboardShortcut("s")
            .disabled(manager.activeEditorSession == nil)

            Button("Save As...") {
                manager.saveActiveEditorAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(manager.activeEditorSession == nil)

            Divider()

            Button("Open in Editor") {
                manager.showOpenPanel = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("Shell") {
            Button("Restart Shell") {
                guard let session = manager.activeSession else { return }
                session.stop()
                session.start(
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory,
                    bottomAlign: settingsStore.settings.inputBarEnabled
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(settingsStore.settings.inputBarEnabled ? "Hide Input Editor" : "Show Input Editor") {
                settingsStore.settings.inputBarEnabled.toggle()
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .toggleInputBar, fallback: KeyShortcut(key: "l", modifiers: [.command, .shift])))
        }

        CommandGroup(before: .toolbar) {
            Button("Split Right") { manager.splitActivePaneFromDefaults(direction: .horizontal) }
                .keyboardShortcut(settingsStore.resolvedShortcut(for: .splitRight, fallback: KeyShortcut(key: "d", modifiers: [.command])))

            Button("Split Down") { manager.splitActivePaneFromDefaults(direction: .vertical) }
                .keyboardShortcut(settingsStore.resolvedShortcut(for: .splitDown, fallback: KeyShortcut(key: "d", modifiers: [.command, .shift])))

            Divider()

            Button("New Editor") {
                let s = settingsStore.settings
                let cursorCfg = s.cursorStyle.editorCursorConfig(color: hexToColorU8(settingsStore.activeTheme.cursor))
                manager.splitActivePaneWithEditor(
                    direction: .horizontal,
                    theme: settingsStore.activeTheme,
                    fontFamily: s.fontFamily,
                    fontSize: s.fontSize,
                    cursorConfig: cursorCfg,
                    cursorBlink: s.cursorBlink
                )
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Panes") {
            Button("Focus Next Pane") {
                manager.selectNextPane()
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .focusNextPane, fallback: KeyShortcut(key: "]", modifiers: [.command, .option])))

            Button("Focus Previous Pane") {
                manager.selectPreviousPane()
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .focusPrevPane, fallback: KeyShortcut(key: "[", modifiers: [.command, .option])))

            Divider()

            Button("Focus Pane Left") {
                manager.selectAdjacentPane(.left)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Button("Focus Pane Right") {
                manager.selectAdjacentPane(.right)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

            Button("Focus Pane Up") {
                manager.selectAdjacentPane(.up)
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])

            Button("Focus Pane Down") {
                manager.selectAdjacentPane(.down)
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        CommandMenu("Tabs") {
            Button("Show Previous Tab") {
                manager.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Show Next Tab") {
                manager.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Divider()

            ForEach(0..<9, id: \.self) { index in
                Button("Tab \(index + 1)") {
                    manager.selectTab(atIndex: index)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}

private extension View {
    func keyboardShortcut(_ shortcut: KeyShortcut) -> some View {
        self.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
    }
}
