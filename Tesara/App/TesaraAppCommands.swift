import AppKit
import Sparkle
import SwiftUI

struct TesaraAppCommands: Commands {
    @ObservedObject var manager: WorkspaceManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var blockStore: BlockStore
    let updater: SPUUpdater

    var body: some Commands {
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
            .keyboardShortcut("t")

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
            .keyboardShortcut("w", modifiers: [.command, .shift])
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

        CommandGroup(after: .toolbar) {
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
}
