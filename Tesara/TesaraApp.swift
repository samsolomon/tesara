import Sparkle
import SwiftUI

@main
struct TesaraApp: App {
    private let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

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
                .onAppear {
                    updaterController.updater.automaticallyChecksForUpdates = settingsStore.settings.updateChecksEnabled
                    GhosttyApp.shared.initialize(
                        theme: settingsStore.activeTheme,
                        settings: settingsStore.settings
                    )
                }
                .onChange(of: settingsStore.settings.updateChecksEnabled) {
                    updaterController.updater.automaticallyChecksForUpdates = settingsStore.settings.updateChecksEnabled
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            TesaraAppCommands(manager: workspaceManager, settingsStore: settingsStore, blockStore: blockStore, updater: updaterController.updater)
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .frame(width: 720, height: 520)
        }
    }
}
