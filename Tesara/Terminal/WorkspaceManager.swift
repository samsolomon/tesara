import AppKit
import Combine
import Foundation

/// Protocol for routing Ghostty keybinding actions to workspace operations.
/// Handlers take the originating session so they operate on the correct tab/pane,
/// not just whatever happens to be "active."
@MainActor protocol GhosttyActionDelegate: AnyObject {
    func ghosttyNewTab(inheritingFrom session: TerminalSession?)
    func ghosttyCloseTab(for session: TerminalSession)
    func ghosttyCloseOtherTabs(for session: TerminalSession)
    func ghosttyCloseTabsToRight(of session: TerminalSession)
    func ghosttyClosePane(for session: TerminalSession)
    func ghosttySplit(for session: TerminalSession, direction: PaneNode.SplitDirection, newPanePosition: PaneNode.PanePosition)
    func ghosttyCloseWindow()
    func ghosttyRequestQuit()
}

@MainActor
final class WorkspaceManager: ObservableObject {
    enum CloseConfirmationRequest: Identifiable, Equatable {
        case dirtyPane(UUID)
        case dirtyTab(UUID)
        case runningPane(UUID)
        case runningTab(UUID)

        var id: String {
            switch self {
            case .dirtyPane(let id):
                "dirty-pane-\(id.uuidString)"
            case .dirtyTab(let id):
                "dirty-tab-\(id.uuidString)"
            case .runningPane(let id):
                "running-pane-\(id.uuidString)"
            case .runningTab(let id):
                "running-tab-\(id.uuidString)"
            }
        }
    }

    struct Tab: Identifiable {
        let id = UUID()
        var rootPane: PaneNode
        var selectedPaneID: UUID
        var title: String
    }

    @Published var tabs: [Tab] = []
    @Published var activeTabID: UUID?
    @Published var activePaneID: UUID?

    // File I/O state
    @Published var showOpenPanel: Bool = false
    @Published var pendingSavePanel: UUID?
    @Published var pendingCloseConfirmation: CloseConfirmationRequest?
    @Published var pendingStaleReload: UUID?
    @Published var lastFileError: Error?

    var sessionFactory: () -> TerminalSession = { TerminalSession() }
    weak var settingsStore: SettingsStore?
    weak var blockStore: BlockStore?
    private var confirmOnCloseRunningSessionEnabled = false
    private var tabTitleMode: TabTitleMode = .shellTitle
    private var paneObservers: [UUID: AnyCancellable] = [:]
    private var pendingSaveContinuation: PendingSaveContinuation?

    private enum PendingSaveContinuation {
        case closePane(UUID)
        case closeTab(UUID, remainingEditorSessionIDs: [UUID])
    }

    func newTab(shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        let session = sessionFactory()
        session.configure(blockStore: blockStore)
        let paneID = UUID()
        let tab = Tab(rootPane: .leaf(id: paneID, session: session), selectedPaneID: paneID, title: "Shell")
        tabs.append(tab)
        activeTabID = tab.id
        activePaneID = paneID
        let bottomAlign = settingsStore?.settings.inputBarEnabled ?? false
        session.start(shellPath: shellPath, workingDirectory: workingDirectory, bottomAlign: bottomAlign)
        refreshWorkspaceMetadata()
    }

    func closeTab(id: UUID) {
        if dirtyEditorSessionIDs(inTabID: id).isEmpty == false {
            pendingCloseConfirmation = .dirtyTab(id)
            return
        }

        if confirmOnCloseRunningSessionEnabled, tabContainsRunningTerminal(tabID: id) {
            pendingCloseConfirmation = .runningTab(id)
            return
        }

        performCloseTab(id: id)
    }

    private func performCloseTab(id: UUID) {
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
                activePaneID = resolvedSelectedPaneID(for: tabs[newIndex])
            }
        }

        refreshWorkspaceMetadata()
    }

    func selectTab(id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        activeTabID = id
        let selectedPaneID = resolvedSelectedPaneID(for: tabs[tabIndex])
        tabs[tabIndex].selectedPaneID = selectedPaneID
        activePaneID = selectedPaneID
        refreshWorkspaceMetadata()
    }

    private func resolvedSelectedPaneID(for tab: Tab) -> UUID {
        if tab.rootPane.contains(paneID: tab.selectedPaneID) {
            return tab.selectedPaneID
        }

        return tab.rootPane.allLeafIDs().first ?? tab.selectedPaneID
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

    var activeEditorSession: EditorSession? {
        guard let activePaneID, let activeTab else { return nil }
        return activeTab.rootPane.findEditorSession(forPaneID: activePaneID)
    }

    // MARK: - Split Panes

    /// Find the tab and pane IDs for a given terminal session.
    func tabAndPaneID(for session: TerminalSession) -> (tabID: UUID, paneID: UUID)? {
        for tab in tabs {
            for (paneID, s) in tab.rootPane.allTerminalSessions() {
                if s === session { return (tab.id, paneID) }
            }
        }
        return nil
    }

    func splitActivePaneFromDefaults(direction: PaneNode.SplitDirection) {
        guard let settingsStore, let blockStore else { return }
        splitActivePane(
            direction: direction,
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }

    func newTabFromDefaults() {
        guard let settingsStore, let blockStore else { return }
        newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }

    func splitActivePane(direction: PaneNode.SplitDirection, position: PaneNode.PanePosition = .second, shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        guard let activePaneID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              tabs[tabIndex].rootPane.contains(paneID: activePaneID) else { return }

        performSplit(
            tabIndex: tabIndex, paneID: activePaneID,
            direction: direction, position: position,
            shellPath: shellPath, workingDirectory: workingDirectory, blockStore: blockStore
        )
    }

    /// Split for a specific session (used by Ghostty action handlers).
    func splitPane(for session: TerminalSession, direction: PaneNode.SplitDirection, position: PaneNode.PanePosition, shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        guard let (tabID, paneID) = tabAndPaneID(for: session),
              let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        activeTabID = tabs[tabIndex].id
        performSplit(
            tabIndex: tabIndex, paneID: paneID,
            direction: direction, position: position,
            shellPath: shellPath, workingDirectory: workingDirectory, blockStore: blockStore
        )
    }

    private func performSplit(tabIndex: Int, paneID: UUID, direction: PaneNode.SplitDirection, position: PaneNode.PanePosition, shellPath: String, workingDirectory: URL, blockStore: BlockStore) {
        // Estimate the new pane's size from the existing pane so the PTY
        // starts with the correct dimensions before SwiftUI lays out the view.
        let initialSize: NSSize? = tabs[tabIndex].rootPane
            .findSession(forPaneID: paneID)?.surfaceView.map { view in
                switch direction {
                case .horizontal: NSSize(width: view.contentSize.width / 2, height: view.contentSize.height)
                case .vertical: NSSize(width: view.contentSize.width, height: view.contentSize.height / 2)
                }
            }

        let newSession = sessionFactory()
        newSession.configure(blockStore: blockStore)
        let newPaneID = UUID()
        let newLeaf = PaneNode.leaf(id: newPaneID, session: newSession)

        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.insertingPane(
            id: paneID,
            newPane: newLeaf,
            direction: direction,
            position: position
        )
        tabs[tabIndex].selectedPaneID = newPaneID
        activePaneID = newPaneID
        let bottomAlign = settingsStore?.settings.inputBarEnabled ?? false
        newSession.start(shellPath: shellPath, workingDirectory: workingDirectory, bottomAlign: bottomAlign, initialSize: initialSize)
        refreshWorkspaceMetadata()
    }

    func splitActivePaneWithEditor(direction: PaneNode.SplitDirection, theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        guard let activePaneID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              tabs[tabIndex].rootPane.contains(paneID: activePaneID) else { return }

        let editorSession = EditorSession()
        editorSession.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorConfig, cursorBlink: cursorBlink)
        let newPaneID = UUID()
        let newEditor = PaneNode.editor(id: newPaneID, session: editorSession)

        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.insertingPane(
            id: activePaneID,
            newPane: newEditor,
            direction: direction,
            position: .second
        )
        tabs[tabIndex].selectedPaneID = newPaneID
        self.activePaneID = newPaneID
        refreshWorkspaceMetadata()
    }

    func closePane(id: UUID) {
        if let activeTabID,
           let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
           let editorSession = tabs[tabIndex].rootPane.findEditorSession(forPaneID: id),
           editorSession.isDirty {
            pendingCloseConfirmation = .dirtyPane(id)
            return
        }

        if confirmOnCloseRunningSessionEnabled, paneContainsRunningTerminal(paneID: id) {
            pendingCloseConfirmation = .runningPane(id)
            return
        }

        performClosePane(id: id)
    }

    private func performClosePane(id: UUID) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        // Stop the terminal session being closed (editor sessions need no stop)
        if let session = tabs[tabIndex].rootPane.findSession(forPaneID: id) {
            session.stop()
        }

        if let newRoot = tabs[tabIndex].rootPane.removingPane(id: id) {
            tabs[tabIndex].rootPane = newRoot
            let newSelectedPaneID = newRoot.contains(paneID: tabs[tabIndex].selectedPaneID)
                ? tabs[tabIndex].selectedPaneID
                : (newRoot.allLeafIDs().first ?? tabs[tabIndex].selectedPaneID)
            tabs[tabIndex].selectedPaneID = newSelectedPaneID
            if activePaneID == id {
                activePaneID = newSelectedPaneID
            }
            refreshWorkspaceMetadata()
        } else {
            // Last pane in tab — close the tab
            performCloseTab(id: tabs[tabIndex].id)
        }
    }

    func updatePaneRatio(splitID: UUID, ratio: CGFloat) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        #if DEBUG
        let requestedRatio = String(format: "%.4f", Double(ratio))
        LocalLogStore.shared.log("[SplitDrag] split=\(splitID.uuidString) requestedRatio=\(requestedRatio)")
        #endif
        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.updatingRatio(splitID: splitID, ratio: ratio)
        refreshWorkspaceMetadata()
    }

    func selectPane(id: UUID) {
        guard id != activePaneID else { return }
        let previousPaneID = activePaneID
        activePaneID = id

        guard let activeTabID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        tabs[tabIndex].selectedPaneID = id
        let activeTab = tabs[tabIndex]
        refreshWorkspaceMetadata()

        // Defocus previous pane
        if let previousPaneID {
            if let prevTermSession = activeTab.rootPane.findSession(forPaneID: previousPaneID) {
                prevTermSession.surfaceView?.focusDidChange(false)
            } else if let prevEditorSession = activeTab.rootPane.findEditorSession(forPaneID: previousPaneID) {
                (prevEditorSession.editorView as? EditorView)?.focusDidChange(false)
            }
        }

        // Focus new pane
        if let newTermSession = activeTab.rootPane.findSession(forPaneID: id) {
            newTermSession.surfaceView?.focusDidChange(true)
            if let surface = newTermSession.surfaceView?.surface {
                GhosttyApp.shared.setFocusedSurface(surface)
            }
        } else if let newEditorSession = activeTab.rootPane.findEditorSession(forPaneID: id) {
            (newEditorSession.editorView as? EditorView)?.focusDidChange(true)
            // Check for stale file on focus gain
            if newEditorSession.filePath != nil, newEditorSession.checkFileStale() {
                pendingStaleReload = id
            }
        }
    }

    func selectNextPane() { selectPaneByOffset(1) }
    func selectPreviousPane() { selectPaneByOffset(-1) }

    private func selectPaneByOffset(_ offset: Int) {
        guard let activePaneID,
              let activeTabID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        let leafIDs = tabs[tabIndex].rootPane.allLeafIDs()
        guard leafIDs.count > 1,
              let currentIndex = leafIDs.firstIndex(of: activePaneID) else { return }

        let newIndex = (currentIndex + offset + leafIDs.count) % leafIDs.count
        selectPane(id: leafIDs[newIndex])
    }

    @discardableResult
    func selectAdjacentPane(_ direction: PaneNode.NavigationDirection) -> Bool {
        guard let activePaneID,
              let activeTabID,
              let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              let adjacentID = tabs[tabIndex].rootPane.adjacentPaneID(to: activePaneID, direction: direction) else {
            return false
        }

        selectPane(id: adjacentID)
        return true
    }

    // MARK: - File I/O

    func openFileInEditor(url: URL, theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        // Check for duplicate: if already open, focus that pane
        for tab in tabs {
            for (paneID, session) in tab.rootPane.allEditorSessions() {
                if session.filePath == url {
                    selectTab(id: tab.id)
                    selectPane(id: paneID)
                    return
                }
            }
        }

        // Create a new editor pane with the file
        let editorSession = EditorSession()
        editorSession.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorConfig, cursorBlink: cursorBlink)

        do {
            try editorSession.loadFile(url: url)
        } catch {
            lastFileError = error
            return
        }

        guard let tabIndex = tabs.firstIndex(where: { $0.id == activeTabID }),
              let activePaneID else { return }

        let currentNode: PaneNode
        if let termSession = tabs[tabIndex].rootPane.findSession(forPaneID: activePaneID) {
            currentNode = .leaf(id: activePaneID, session: termSession)
        } else if let editorSess = tabs[tabIndex].rootPane.findEditorSession(forPaneID: activePaneID) {
            currentNode = .editor(id: activePaneID, session: editorSess)
        } else {
            return
        }

        let newPaneID = UUID()
        let newEditor = PaneNode.editor(id: newPaneID, session: editorSession)
        let splitNode = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            first: currentNode,
            second: newEditor,
            ratio: 0.5
        )

        tabs[tabIndex].rootPane = tabs[tabIndex].rootPane.replacingPane(id: activePaneID, with: splitNode)
        tabs[tabIndex].selectedPaneID = newPaneID
        self.activePaneID = newPaneID
        refreshWorkspaceMetadata()
    }

    func saveActiveEditor() {
        guard let session = activeEditorSession else { return }
        if session.filePath != nil {
            do {
                try session.save()
            } catch {
                lastFileError = error
            }
        } else {
            pendingSavePanel = session.id
        }
    }

    func saveActiveEditorAs() {
        guard let session = activeEditorSession else { return }
        pendingSavePanel = session.id
    }

    var activeTabTitle: String {
        activeTab?.title ?? "Shell"
    }

    enum CloseResolution {
        case save
        case discard
        case cancel
    }

    func resolvePendingClose(_ resolution: CloseResolution) {
        guard let request = pendingCloseConfirmation else { return }
        pendingCloseConfirmation = nil

        guard resolution != .cancel else { return }

        switch request {
        case .dirtyPane(let paneID):
            if resolution == .save {
                saveDirtyPaneAndClose(id: paneID)
            } else {
                performClosePane(id: paneID)
            }

        case .dirtyTab(let tabID):
            if resolution == .save {
                saveDirtyEditorsAndCloseTab(id: tabID)
            } else {
                continueClosingTabAfterDirtyResolution(id: tabID)
            }

        case .runningPane(let paneID):
            performClosePane(id: paneID)

        case .runningTab(let tabID):
            performCloseTab(id: tabID)
        }
    }

    func completePendingSavePanel(sessionID: UUID, url: URL) {
        guard pendingSavePanel == sessionID else { return }
        guard let session = editorSession(withID: sessionID) else {
            cancelPendingSavePanel()
            return
        }

        do {
            try session.saveAs(url: url)
        } catch {
            lastFileError = error
            cancelPendingSavePanel()
            return
        }

        pendingSavePanel = nil
        let continuation = pendingSaveContinuation
        pendingSaveContinuation = nil
        if let continuation {
            handlePendingSaveSuccess(continuation)
        }
    }

    func cancelPendingSavePanel() {
        pendingSavePanel = nil
        pendingSaveContinuation = nil
    }

    /// Save the editor session associated with a specific pane (not necessarily the active one).
    private func saveEditorForPane(id: UUID) {
        guard let session = editorSession(forPaneID: id) else { return }
        if session.filePath != nil {
            do {
                try session.save()
            } catch {
                lastFileError = error
            }
        } else {
            pendingSavePanel = session.id
        }
    }

    func setConfirmOnCloseRunningSessionEnabled(_ enabled: Bool) {
        confirmOnCloseRunningSessionEnabled = enabled
    }

    func setTabTitleMode(_ mode: TabTitleMode) {
        guard tabTitleMode != mode else { return }
        tabTitleMode = mode
        refreshTabTitles()
    }

    // MARK: - Helpers

    private func refreshWorkspaceMetadata() {
        refreshPaneObservers()
        refreshTabTitles()
    }

    private func saveDirtyPaneAndClose(id paneID: UUID) {
        guard let session = editorSession(forPaneID: paneID) else { return }
        requestSave(for: session, continuation: .closePane(paneID))
    }

    private func saveDirtyEditorsAndCloseTab(id tabID: UUID) {
        continueSavingDirtyEditorsAndCloseTab(id: tabID, remainingEditorSessionIDs: dirtyEditorSessionIDs(inTabID: tabID))
    }

    private func continueSavingDirtyEditorsAndCloseTab(id tabID: UUID, remainingEditorSessionIDs: [UUID]) {
        let remainingDirtySessionIDs = remainingEditorSessionIDs.filter { sessionID in
            editorSession(withID: sessionID)?.isDirty == true
        }

        guard let nextSessionID = remainingDirtySessionIDs.first else {
            continueClosingTabAfterDirtyResolution(id: tabID)
            return
        }

        guard let session = editorSession(withID: nextSessionID) else {
            continueSavingDirtyEditorsAndCloseTab(id: tabID, remainingEditorSessionIDs: Array(remainingDirtySessionIDs.dropFirst()))
            return
        }

        requestSave(
            for: session,
            continuation: .closeTab(tabID, remainingEditorSessionIDs: Array(remainingDirtySessionIDs.dropFirst()))
        )
    }

    private func requestSave(for session: EditorSession, continuation: PendingSaveContinuation) {
        if session.filePath != nil {
            do {
                try session.save()
                handlePendingSaveSuccess(continuation)
            } catch {
                lastFileError = error
            }
            return
        }

        pendingSaveContinuation = continuation
        pendingSavePanel = session.id
    }

    private func handlePendingSaveSuccess(_ continuation: PendingSaveContinuation) {
        switch continuation {
        case .closePane(let paneID):
            performClosePane(id: paneID)
        case .closeTab(let tabID, let remainingEditorSessionIDs):
            continueSavingDirtyEditorsAndCloseTab(id: tabID, remainingEditorSessionIDs: remainingEditorSessionIDs)
        }
    }

    private func continueClosingTabAfterDirtyResolution(id tabID: UUID) {
        if confirmOnCloseRunningSessionEnabled, tabContainsRunningTerminal(tabID: tabID) {
            pendingCloseConfirmation = .runningTab(tabID)
            return
        }

        performCloseTab(id: tabID)
    }

    private func refreshPaneObservers() {
        var activePaneIDs = Set<UUID>()

        for tab in tabs {
            for (paneID, session) in tab.rootPane.allTerminalSessions() {
                activePaneIDs.insert(paneID)
                if paneObservers[paneID] == nil {
                    paneObservers[paneID] = session.objectWillChange.sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.refreshTabTitles()
                        }
                    }
                }
            }

            for (paneID, session) in tab.rootPane.allEditorSessions() {
                activePaneIDs.insert(paneID)
                if paneObservers[paneID] == nil {
                    paneObservers[paneID] = session.objectWillChange.sink { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.refreshTabTitles()
                        }
                    }
                }
            }
        }

        let obsoletePaneIDs = Set(paneObservers.keys).subtracting(activePaneIDs)
        for paneID in obsoletePaneIDs {
            paneObservers[paneID]?.cancel()
            paneObservers.removeValue(forKey: paneID)
        }
    }

    private func refreshTabTitles() {
        for index in tabs.indices {
            let nextTitle = makeTitle(for: tabs[index])
            if tabs[index].title != nextTitle {
                tabs[index].title = nextTitle
            }
        }
    }

    private func makeTitle(for tab: Tab) -> String {
        let paneID = resolvedSelectedPaneID(for: tab)

        if let editorSession = tab.rootPane.findEditorSession(forPaneID: paneID) {
            return editorSession.displayTitle
        }

        if let terminalSession = tab.rootPane.findSession(forPaneID: paneID) {
            let shellTitle = normalizedTitle(from: terminalSession.shellTitle)
            let workingDirectoryTitle = workingDirectoryTitle(for: terminalSession.currentWorkingDirectory)

            switch tabTitleMode {
            case .shellTitle:
                if let shellTitle {
                    return shellTitle
                }
                if let workingDirectoryTitle {
                    return workingDirectoryTitle
                }
            case .workingDirectory:
                if let workingDirectoryTitle {
                    return workingDirectoryTitle
                }
                if let shellTitle {
                    return shellTitle
                }
            }
        }

        return "Shell"
    }

    private func normalizedTitle(from rawTitle: String?) -> String? {
        guard let rawTitle else { return nil }
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func workingDirectoryTitle(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }

        let url = URL(fileURLWithPath: path)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path == homePath {
            return "~"
        }

        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty {
            return lastComponent
        }

        return url.path
    }

    private func resolvedWorkingDirectory(from session: TerminalSession?) -> URL {
        if let cwd = session?.currentWorkingDirectory {
            return URL(fileURLWithPath: cwd)
        }
        return settingsStore?.settings.defaultWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    private func paneContainsRunningTerminal(paneID: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.rootPane.contains(paneID: paneID) }),
              let session = tab.rootPane.findSession(forPaneID: paneID) else {
            return false
        }

        return session.status == .running || session.status == .starting
    }

    private func tabContainsRunningTerminal(tabID: UUID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return false }
        return tab.rootPane
            .allTerminalSessions()
            .contains { _, session in
                session.status == .running || session.status == .starting
            }
    }

    private func dirtyEditorSessionIDs(inTabID tabID: UUID) -> [UUID] {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return [] }
        return tab.rootPane
            .allEditorSessions()
            .map(\.session)
            .filter(\.isDirty)
            .map(\.id)
    }

    private func editorSession(forPaneID paneID: UUID) -> EditorSession? {
        for tab in tabs {
            if let session = tab.rootPane.findEditorSession(forPaneID: paneID) {
                return session
            }
        }

        return nil
    }

    private func editorSession(withID sessionID: UUID) -> EditorSession? {
        for tab in tabs {
            for (_, session) in tab.rootPane.allEditorSessions() where session.id == sessionID {
                return session
            }
        }

        return nil
    }

    private func stopAllSessions(in node: PaneNode) {
        switch node {
        case .leaf(_, let session):
            session.stop()
        case .editor:
            break  // Editor sessions need no explicit stop
        case .split(_, _, let first, let second, _):
            stopAllSessions(in: first)
            stopAllSessions(in: second)
        }
    }
}

// MARK: - GhosttyActionDelegate

extension WorkspaceManager: GhosttyActionDelegate {
    func ghosttyNewTab(inheritingFrom session: TerminalSession?) {
        guard let settingsStore, let blockStore else { return }
        newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: resolvedWorkingDirectory(from: session),
            blockStore: blockStore
        )
    }

    func ghosttyCloseTab(for session: TerminalSession) {
        guard let (tabID, _) = tabAndPaneID(for: session) else { return }
        closeTab(id: tabID)
    }

    func ghosttyCloseOtherTabs(for session: TerminalSession) {
        guard let (tabID, _) = tabAndPaneID(for: session) else { return }
        let otherTabIDs = tabs.map(\.id).filter { $0 != tabID }
        for id in otherTabIDs {
            closeTab(id: id)
        }
    }

    func ghosttyCloseTabsToRight(of session: TerminalSession) {
        guard let (tabID, _) = tabAndPaneID(for: session),
              let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let rightTabIDs = tabs[(tabIndex + 1)...].map(\.id)
        for id in rightTabIDs {
            closeTab(id: id)
        }
    }

    func ghosttyClosePane(for session: TerminalSession) {
        guard let (_, paneID) = tabAndPaneID(for: session) else { return }
        closePane(id: paneID)
    }

    func ghosttySplit(for session: TerminalSession, direction: PaneNode.SplitDirection, newPanePosition: PaneNode.PanePosition) {
        guard let settingsStore, let blockStore else { return }
        splitPane(
            for: session,
            direction: direction,
            position: newPanePosition,
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: resolvedWorkingDirectory(from: session),
            blockStore: blockStore
        )
    }

    func ghosttyCloseWindow() {
        guard confirmAllTabsClean() else { return }
        NSApp.keyWindow?.close()
    }

    func ghosttyRequestQuit() {
        guard confirmAllTabsClean() else { return }
        NSApp.terminate(nil)
    }

    /// Checks all tabs for unsaved work. Returns true if all are clean.
    /// If any tab has dirty editors or running terminals, sets `pendingCloseConfirmation` and returns false.
    private func confirmAllTabsClean() -> Bool {
        for tab in tabs {
            if !dirtyEditorSessionIDs(inTabID: tab.id).isEmpty {
                pendingCloseConfirmation = .dirtyTab(tab.id)
                return false
            }
            if tabContainsRunningTerminal(tabID: tab.id) {
                pendingCloseConfirmation = .runningTab(tab.id)
                return false
            }
        }
        return true
    }
}
