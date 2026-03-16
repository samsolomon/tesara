import Sparkle
import SwiftUI

@main
struct TesaraApp: App {
    private let minimumWindowSize = CGSize(width: 120, height: 80)
    private let updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var blockStore = BlockStore()
    @StateObject private var workspaceManager = WorkspaceManager()
    @StateObject private var keyBindingDispatcher = KeyBindingDispatcher()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .environmentObject(workspaceManager)
                .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
                .onAppear {
                    CrashHandler.install()
                    updaterController.updater.automaticallyChecksForUpdates = settingsStore.settings.updateChecksEnabled
                    blockStore.setHistoryCaptureEnabled(settingsStore.settings.historyCaptureEnabled)
                    LocalLogStore.shared.setEnabled(settingsStore.settings.localLoggingEnabled)
                    workspaceManager.setConfirmOnCloseRunningSessionEnabled(settingsStore.settings.confirmOnCloseRunningSession)
                    workspaceManager.setTabTitleMode(settingsStore.settings.tabTitleMode)
                    TerminalSession.cleanupStaleTempFiles()
                    GhosttyApp.shared.initialize(
                        theme: settingsStore.activeTheme,
                        settings: settingsStore.settings
                    )
                    workspaceManager.settingsStore = settingsStore
                    workspaceManager.blockStore = blockStore
                    GhosttyApp.shared.actionDelegate = workspaceManager
                    keyBindingDispatcher.configure(
                        settingsStore: settingsStore,
                        workspaceManager: workspaceManager,
                        blockStore: blockStore
                    )
                    SettingsWindowController.shared.configure(
                        settingsStore: settingsStore,
                        blockStore: blockStore,
                        updater: updaterController.updater
                    )
                }
                .onChange(of: settingsStore.settings.updateChecksEnabled) {
                    updaterController.updater.automaticallyChecksForUpdates = settingsStore.settings.updateChecksEnabled
                }
                .onChange(of: settingsStore.settings.historyCaptureEnabled) {
                    blockStore.setHistoryCaptureEnabled(settingsStore.settings.historyCaptureEnabled)
                }
                .onChange(of: settingsStore.settings.localLoggingEnabled) {
                    LocalLogStore.shared.setEnabled(settingsStore.settings.localLoggingEnabled)
                }
                .onChange(of: settingsStore.settings.confirmOnCloseRunningSession) {
                    workspaceManager.setConfirmOnCloseRunningSessionEnabled(settingsStore.settings.confirmOnCloseRunningSession)
                }
                .onChange(of: settingsStore.settings.tabTitleMode) {
                    workspaceManager.setTabTitleMode(settingsStore.settings.tabTitleMode)
                }
                .onChange(of: settingsStore.settings.pasteProtectionMode) {
                    GhosttyApp.shared.updateConfig(
                        theme: settingsStore.activeTheme,
                        settings: settingsStore.settings
                    )
                }
                .onChange(of: settingsStore.ghosttyConfigInputs) {
                    GhosttyApp.shared.updateConfig(
                        theme: settingsStore.activeTheme,
                        settings: settingsStore.settings
                    )
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            TesaraAppCommands(
                manager: workspaceManager,
                settingsStore: settingsStore,
                updater: updaterController.updater
            )
        }

    }

}
