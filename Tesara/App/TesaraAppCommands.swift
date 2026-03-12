import AppKit
import SwiftUI

struct TesaraAppCommands: Commands {
    @ObservedObject var manager: WorkspaceManager
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var blockStore: BlockStore

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
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

            Button("Close Tab") {
                if let id = manager.activeTabID {
                    manager.closeTab(id: id)
                }
            }
            .keyboardShortcut("w")
        }

        CommandGroup(before: .toolbar) {
            Button("Split Right") {
                manager.splitActivePane(
                    direction: .horizontal,
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory,
                    blockStore: blockStore
                )
            }
            .keyboardShortcut("d")

            Button("Split Down") {
                manager.splitActivePane(
                    direction: .vertical,
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory,
                    blockStore: blockStore
                )
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
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
}
