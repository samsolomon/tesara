import AppKit
import Sparkle
import SwiftUI

struct TesaraAppCommands: Commands {
    @ObservedObject var manager: WorkspaceManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var blockStore: BlockStore
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                manager.newTab(
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory,
                    blockStore: blockStore
                )
            }
            .keyboardShortcut(settingsStore.resolvedShortcut(for: .newTab, fallback: KeyShortcut(key: "t", modifiers: [.command])))

            Button("Close Pane") {
                if let id = manager.activePaneID {
                    manager.closePane(id: id)
                }
            }
            .keyboardShortcut("w")

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
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button("Split Right") { split(.horizontal) }
                .keyboardShortcut("d")

            Button("Split Down") { split(.vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])

            Divider()

            Button("New Editor") {
                manager.splitActivePaneWithEditor(
                    direction: .horizontal,
                    theme: settingsStore.activeTheme,
                    fontFamily: settingsStore.settings.fontFamily,
                    fontSize: settingsStore.settings.fontSize
                )
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandMenu("Panes") {
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

    private func split(_ direction: PaneNode.SplitDirection) {
        manager.splitActivePane(
            direction: direction,
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }

    private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

private extension View {
    func keyboardShortcut(_ shortcut: KeyShortcut) -> some View {
        self.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
    }
}
