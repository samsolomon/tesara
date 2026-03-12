import SwiftUI

@main
struct TesaraApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var blockStore = BlockStore()
    @StateObject private var workspaceManager = WorkspaceManager()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .environmentObject(workspaceManager)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            TesaraAppCommands(manager: workspaceManager, settingsStore: settingsStore, blockStore: blockStore)
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .frame(width: 720, height: 520)
        }
    }
}
