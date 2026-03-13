import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @EnvironmentObject private var workspaceManager: WorkspaceManager

    private var showTabBar: Bool {
        workspaceManager.tabs.count > 1
    }

    var body: some View {
        TerminalWorkspaceView(manager: workspaceManager)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .top, spacing: 0) {
                if showTabBar {
                    TitleBarTabStrip(manager: workspaceManager, isDarkBackground: settingsStore.activeTheme.isDarkBackground, onNewTab: addTab)
                        .padding(.vertical, 4)
                }
            }
    }

    private func addTab() {
        workspaceManager.newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }
}

#Preview {
    MainWindowView()
        .environmentObject(SettingsStore())
        .environmentObject(BlockStore())
        .environmentObject(WorkspaceManager())
}
