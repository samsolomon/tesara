import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @EnvironmentObject private var workspaceManager: WorkspaceManager

    var body: some View {
        TerminalWorkspaceView(manager: workspaceManager)
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleBarTabStrip(manager: workspaceManager, onNewTab: addTab)
                }
            }
    }

    private func addTab() {
        workspaceManager.newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore,
            useGhosttyRenderer: settingsStore.settings.useGhosttyRenderer
        )
    }
}

#Preview {
    MainWindowView()
        .environmentObject(SettingsStore())
        .environmentObject(BlockStore())
        .environmentObject(WorkspaceManager())
}
