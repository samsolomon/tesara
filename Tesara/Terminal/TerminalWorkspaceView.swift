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
                let isActive = tab.id == manager.activeTabID
                PaneContainerView(
                    node: tab.rootPane,
                    theme: settingsStore.activeTheme,
                    activePaneID: manager.activePaneID,
                    onSelectPane: { paneID in
                        manager.selectPane(id: paneID)
                    },
                    onUpdateRatio: { splitID, ratio in
                        manager.updatePaneRatio(splitID: splitID, ratio: ratio)
                    }
                )
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
                .onChange(of: isActive) { _, nowActive in
                    setOcclusion(for: tab.rootPane, occluded: !nowActive)
                }
            }
        }
    }

    private func setOcclusion(for node: PaneNode, occluded: Bool) {
        switch node {
        case .leaf(_, let session):
            if let surface = session.surfaceView?.surface {
                ghostty_surface_set_occlusion(surface, occluded)
            }
        case .split(_, _, let first, let second, _):
            setOcclusion(for: first, occluded: occluded)
            setOcclusion(for: second, occluded: occluded)
        }
    }
}
