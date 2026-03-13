import Foundation

@MainActor
final class WorkspaceManager: ObservableObject {
    struct Tab: Identifiable {
        let id = UUID()
        var rootPane: PaneNode
        var title: String
    }

    @Published var tabs: [Tab] = []
    @Published var activeTabID: UUID?
    @Published var activePaneID: UUID?

    var sessionFactory: () -> TerminalSession = { TerminalSession() }

    func newTab(shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        let session = sessionFactory()
        session.configure(blockStore: blockStore)
        let paneID = UUID()
        let tab = Tab(rootPane: .leaf(id: paneID, session: session), title: "Shell")
        tabs.append(tab)
        activeTabID = tab.id
        activePaneID = paneID
        session.start(shellPath: shellPath, workingDirectory: workingDirectory)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        stopAllSessions(in: tabs[index].rootPane)
        tabs.remove(at: index)

        if activeTabID == id {
            if tabs.isEmpty {
                activeTabID = nil
                activePaneID = nil
            } else {
                let newIndex = min(index, tabs.count - 1)
                activeTabID = tabs[newIndex].id
                activePaneID = tabs[newIndex].rootPane.allLeafIDs().first
            }
        }
    }

    func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        if let tab = tabs.first(where: { $0.id == id }) {
            if let currentPane = activePaneID, tab.rootPane.contains(paneID: currentPane) {
                // Keep current pane selection
            } else {
                activePaneID = tab.rootPane.allLeafIDs().first
            }
        }
    }

    func selectTab(atIndex index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectTab(id: tabs[index].id)
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count,
              sourceIndex != destinationIndex else { return }
        tabs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
    }

    func selectPreviousTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }), tabs.count > 1 else { return }
        let newIndex = index > 0 ? index - 1 : tabs.count - 1
        selectTab(id: tabs[newIndex].id)
    }

    func selectNextTab() {
        guard let activeTabID, let index = tabs.firstIndex(where: { $0.id == activeTabID }), tabs.count > 1 else { return }
        let newIndex = index < tabs.count - 1 ? index + 1 : 0
        selectTab(id: tabs[newIndex].id)
    }

    var activeTab: Tab? {
        guard let activeTabID else { return nil }
        return tabs.first(where: { $0.id == activeTabID })
    }

    var activeSession: TerminalSession? {
        guard let activePaneID, let activeTab else { return nil }
        return activeTab.rootPane.findSession(forPaneID: activePaneID)
    }

    // MARK: - Split Panes

    func splitActivePane(direction: PaneNode.SplitDirection, shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        guard let activePaneID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              let currentSession = tabs[tabIndex].rootPane.findSession(forPaneID: activePaneID) else { return }

        let newSession = sessionFactory()
        newSession.configure(blockStore: blockStore)
        let newPaneID = UUID()
        let newLeaf = PaneNode.leaf(id: newPaneID, session: newSession)

        let splitNode = PaneNode.split(
            id: UUID(),
            direction: direction,
            first: .leaf(id: activePaneID, session: currentSession),
            second: newLeaf,
            ratio: 0.5
        )

        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.replacingPane(id: activePaneID, with: splitNode)
        self.activePaneID = newPaneID
        newSession.start(shellPath: shellPath, workingDirectory: workingDirectory)
    }

    func closePane(id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        // Stop the session being closed
        if let session = tabs[tabIndex].rootPane.findSession(forPaneID: id) {
            session.stop()
        }

        if let newRoot = tabs[tabIndex].rootPane.removingPane(id: id) {
            tabs[tabIndex].rootPane = newRoot
            if activePaneID == id {
                activePaneID = newRoot.allLeafIDs().first
            }
        } else {
            // Last pane in tab — close the tab
            closeTab(id: tabs[tabIndex].id)
        }
    }

    func updatePaneRatio(splitID: UUID, ratio: CGFloat) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.updatingRatio(splitID: splitID, ratio: ratio)
    }

    func selectPane(id: UUID) {
        guard id != activePaneID else { return }
        let previousPaneID = activePaneID
        activePaneID = id

        // Update ghostty surface focus state for the previous and new pane
        if let activeTab {
            if let previousPaneID,
               let prevSession = activeTab.rootPane.findSession(forPaneID: previousPaneID) {
                prevSession.surfaceView?.focusDidChange(false)
            }
            if let newSession = activeTab.rootPane.findSession(forPaneID: id) {
                newSession.surfaceView?.focusDidChange(true)
                if let surface = newSession.surfaceView?.surface {
                    GhosttyApp.shared.setFocusedSurface(surface)
                }
            }
        }
    }

    // MARK: - Helpers

    private func stopAllSessions(in node: PaneNode) {
        switch node {
        case .leaf(_, let session):
            session.stop()
        case .split(_, _, let first, let second, _):
            stopAllSessions(in: first)
            stopAllSessions(in: second)
        }
    }
}
