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
    @StateObject private var settingsOpenCoordinator = SettingsOpenCoordinator()
    @Environment(\.colorScheme) private var colorScheme

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .environmentObject(workspaceManager)
                .environmentObject(settingsOpenCoordinator)
                .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
                .onAppear {
                    settingsStore.isDark = colorScheme == .dark
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
                        blockStore: blockStore,
                        settingsOpenCoordinator: settingsOpenCoordinator
                    )
                    applyWindowBlur(settingsStore.settings.windowBlur)
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
                .onChange(of: colorScheme) {
                    settingsStore.isDark = colorScheme == .dark
                }
                .onChange(of: settingsStore.settings.windowBlur) {
                    applyWindowBlur(settingsStore.settings.windowBlur)
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            TesaraAppCommands(
                manager: workspaceManager,
                settingsStore: settingsStore,
                blockStore: blockStore,
                settingsOpenCoordinator: settingsOpenCoordinator,
                updater: updaterController.updater
            )
        }

        Settings {
            SettingsView(updater: updaterController.updater)
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .frame(minWidth: 840, minHeight: 560)
        }
    }

    private func applyWindowBlur(_ enabled: Bool) {
        for window in NSApp.windows where window.className.contains("AppKitWindow") {
            window.isOpaque = !enabled
            window.backgroundColor = enabled ? .clear : .windowBackgroundColor
        }
    }
}
