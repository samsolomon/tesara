import SwiftUI

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        terminalContent
            .background(settingsStore.activeTheme.swiftUIColor(from: settingsStore.activeTheme.background))
            .task {
                if manager.tabs.isEmpty {
                    manager.newTab(
                        shellPath: settingsStore.settings.shellPath,
                        workingDirectory: settingsStore.settings.defaultWorkingDirectory,
                        blockStore: blockStore
                    )
                }
            }
    }

    private var terminalContent: some View {
        ZStack {
            ForEach(manager.tabs) { tab in
                PaneContainerView(
                    node: tab.rootPane,
                    theme: settingsStore.activeTheme,
                    fontFamily: settingsStore.settings.fontFamily,
                    fontSize: settingsStore.settings.fontSize,
                    activePaneID: manager.activePaneID,
                    onSelectPane: { paneID in
                        manager.selectPane(id: paneID)
                    },
                    onUpdateRatio: { splitID, ratio in
                        manager.updatePaneRatio(splitID: splitID, ratio: ratio)
                    }
                )
                .opacity(tab.id == manager.activeTabID ? 1 : 0)
                .allowsHitTesting(tab.id == manager.activeTabID)
            }
        }
    }
}
