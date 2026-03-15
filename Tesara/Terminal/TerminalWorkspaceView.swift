import SwiftUI
import UniformTypeIdentifiers

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @ObservedObject var manager: WorkspaceManager

    @State private var showFileError = false
    @State private var showCloseConfirmation = false
    @State private var showStaleReload = false

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
            .onChange(of: settingsStore.activeTheme) { _, newTheme in
                propagateThemeToEditors(theme: newTheme)
                propagateThemeToInputBars(theme: newTheme)
            }
            .onChange(of: settingsStore.settings.fontFamily) { _, newFamily in
                propagateFontToInputBars(family: newFamily, size: settingsStore.settings.fontSize)
            }
            .onChange(of: settingsStore.settings.fontSize) { _, newSize in
                propagateFontToInputBars(family: settingsStore.settings.fontFamily, size: newSize)
            }
            .onChange(of: settingsStore.cursorConfigInputs) { _, _ in
                propagateCursorToEditors()
            }
            .fileImporter(
                isPresented: $manager.showOpenPanel,
                allowedContentTypes: [.plainText, .sourceCode, .data]
            ) { result in
                if case .success(let url) = result {
                    let s = settingsStore.settings
                    let cursorCfg = s.cursorStyle.editorCursorConfig(color: hexToColorU8(settingsStore.activeTheme.cursor))
                    manager.openFileInEditor(
                        url: url,
                        theme: settingsStore.activeTheme,
                        fontFamily: s.fontFamily,
                        fontSize: s.fontSize,
                        cursorConfig: cursorCfg,
                        cursorBlink: true
                    )
                }
            }
            .onChange(of: manager.pendingSavePanel) { _, sessionID in
                guard let sessionID else { return }
                presentSavePanel(for: sessionID)
            }
            .modifier(FileErrorAlert(showAlert: $showFileError, manager: manager))
            .modifier(CloseConfirmationAlert(showAlert: $showCloseConfirmation, manager: manager))
            .modifier(StaleReloadAlert(showAlert: $showStaleReload, manager: manager))
    }

    private var terminalContent: some View {
        ZStack {
            ForEach(manager.tabs) { tab in
                let isActive = tab.id == manager.activeTabID
                PaneContainerView(
                    node: tab.rootPane,
                    theme: settingsStore.activeTheme,
                    fontFamily: settingsStore.settings.fontFamily,
                    fontSize: settingsStore.settings.fontSize,
                    inputBarEnabled: settingsStore.settings.inputBarEnabled,
                    activePaneID: manager.activePaneID,
                    dimInactiveSplits: settingsStore.settings.dimInactiveSplits,
                    inactiveSplitDimAmount: settingsStore.settings.inactiveSplitDimAmount,
                    tabTitleMode: manager.tabTitleMode,
                    onSelectPane: { paneID in
                        manager.selectPane(id: paneID)
                    },
                    onUpdateRatio: { splitID, ratio in
                        manager.updatePaneRatio(splitID: splitID, ratio: ratio)
                    },
                    onClosePane: { paneID in
                        manager.closePane(id: paneID)
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

    // MARK: - File Panels

    private func presentSavePanel(for sessionID: UUID) {
        var targetSession: EditorSession?
        for tab in manager.tabs {
            for (_, session) in tab.rootPane.allEditorSessions() {
                if session.id == sessionID {
                    targetSession = session
                    break
                }
            }
            if targetSession != nil { break }
        }
        guard let session = targetSession else {
            manager.pendingSavePanel = nil
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        if let existing = session.filePath {
            panel.nameFieldStringValue = existing.lastPathComponent
            panel.directoryURL = existing.deletingLastPathComponent()
        }
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else {
                    manager.cancelPendingSavePanel()
                    return
                }
                manager.completePendingSavePanel(sessionID: session.id, url: url)
            }
        }
    }

    // MARK: - Occlusion

    private func setOcclusion(for node: PaneNode, occluded: Bool) {
        switch node {
        case .leaf(_, let session):
            if let surface = session.surfaceView?.surface {
                ghostty_surface_set_occlusion(surface, occluded)
            }
        case .editor(_, let editorSession):
            if let editorView = editorSession.editorView as? EditorView {
                if occluded {
                    editorView.pauseDisplayLink()
                } else {
                    editorView.resumeDisplayLink()
                }
            }
        case .split(_, _, let first, let second, _):
            setOcclusion(for: first, occluded: occluded)
            setOcclusion(for: second, occluded: occluded)
        }
    }

    // MARK: - Theme

    private func propagateThemeToEditors(theme: TerminalTheme) {
        guard let activeTab = manager.activeTab else { return }
        propagateThemeToEditors(in: activeTab.rootPane, theme: theme)
    }

    private func propagateThemeToEditors(in node: PaneNode, theme: TerminalTheme) {
        switch node {
        case .leaf:
            break
        case .editor(_, let editorSession):
            editorSession.updateTheme(theme)
        case .split(_, _, let first, let second, _):
            propagateThemeToEditors(in: first, theme: theme)
            propagateThemeToEditors(in: second, theme: theme)
        }
    }

    private func propagateThemeToInputBars(theme: TerminalTheme) {
        guard let activeTab = manager.activeTab else { return }
        for (_, session) in activeTab.rootPane.allTerminalSessions() {
            session.inputBarState?.editorView?.updateTheme(theme)
        }
    }

    private func propagateFontToInputBars(family: String, size: Double) {
        guard let activeTab = manager.activeTab else { return }
        for (_, session) in activeTab.rootPane.allTerminalSessions() {
            session.inputBarState?.editorView?.updateFont(family: family, size: CGFloat(size))
        }
    }

    private func propagateCursorToEditors() {
        guard let activeTab = manager.activeTab else { return }
        let s = settingsStore.settings
        let theme = settingsStore.activeTheme
        let config = s.cursorStyle.editorCursorConfig(color: hexToColorU8(theme.cursor))
        propagateCursorToEditors(in: activeTab.rootPane, config: config, blink: true, smoothBlink: false)
        for (_, session) in activeTab.rootPane.allTerminalSessions() {
            session.inputBarState?.editorView?.updateCursorConfig(config, blink: true, smoothBlink: false)
        }
    }

    private func propagateCursorToEditors(in node: PaneNode, config: EditorLayoutEngine.CursorConfig, blink: Bool, smoothBlink: Bool) {
        switch node {
        case .leaf:
            break
        case .editor(_, let editorSession):
            editorSession.updateCursorConfig(config, blink: blink, smoothBlink: smoothBlink)
        case .split(_, _, let first, let second, _):
            propagateCursorToEditors(in: first, config: config, blink: blink, smoothBlink: smoothBlink)
            propagateCursorToEditors(in: second, config: config, blink: blink, smoothBlink: smoothBlink)
        }
    }
}

// MARK: - Alert Modifiers (broken out to reduce type-checker complexity)

private struct FileErrorAlert: ViewModifier {
    @Binding var showAlert: Bool
    @ObservedObject var manager: WorkspaceManager

    func body(content: Content) -> some View {
        content
            .onChange(of: manager.lastFileError != nil) { _, hasError in
                showAlert = hasError
            }
            .alert("File Error", isPresented: $showAlert) {
                Button("OK") { manager.lastFileError = nil }
            } message: {
                Text(manager.lastFileError?.localizedDescription ?? "An unknown error occurred.")
            }
    }
}

private struct CloseConfirmationAlert: ViewModifier {
    @Binding var showAlert: Bool
    @ObservedObject var manager: WorkspaceManager

    func body(content: Content) -> some View {
        content
            .onChange(of: manager.pendingCloseConfirmation) { _, request in
                showAlert = request != nil
            }
            .onChange(of: showAlert) { _, isPresented in
                if !isPresented {
                    manager.pendingCloseConfirmation = nil
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                switch manager.pendingCloseConfirmation {
                case .dirtyPane, .dirtyTab:
                    Button("Save") {
                        manager.resolvePendingClose(.save)
                    }
                    Button("Don't Save", role: .destructive) {
                        manager.resolvePendingClose(.discard)
                    }
                case .runningPane, .runningTab:
                    Button("Close", role: .destructive) {
                        manager.resolvePendingClose(.discard)
                    }
                case nil:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {
                    manager.resolvePendingClose(.cancel)
                }
            } message: {
                Text(alertMessage)
            }
    }

    private var alertTitle: String {
        switch manager.pendingCloseConfirmation {
        case .dirtyPane:
            return "Unsaved Changes"
        case .dirtyTab:
            return "Unsaved Changes in Tab"
        case .runningPane, .runningTab:
            return "Close Running Session?"
        case nil:
            return ""
        }
    }

    private var alertMessage: String {
        switch manager.pendingCloseConfirmation {
        case .dirtyPane:
            return "Do you want to save changes before closing?"
        case .dirtyTab:
            return "This tab contains unsaved editor changes. Save them before closing the tab?"
        case .runningPane:
            return "This pane still has a running terminal session. Closing it will stop that session."
        case .runningTab:
            return "This tab still has a running terminal session. Closing it will stop that session."
        case nil:
            return ""
        }
    }
}

private struct StaleReloadAlert: ViewModifier {
    @Binding var showAlert: Bool
    @ObservedObject var manager: WorkspaceManager

    func body(content: Content) -> some View {
        content
            .onChange(of: manager.pendingStaleReload) { _, paneID in
                showAlert = paneID != nil
            }
            .alert("File Changed on Disk", isPresented: $showAlert) {
                Button("Reload") {
                    if let paneID = manager.pendingStaleReload,
                       let tab = manager.activeTab,
                       let session = tab.rootPane.findEditorSession(forPaneID: paneID),
                       let url = session.filePath {
                        try? session.loadFile(url: url)
                    }
                    manager.pendingStaleReload = nil
                }
                Button("Keep Current", role: .cancel) {
                    manager.pendingStaleReload = nil
                }
            } message: {
                Text("The file has been modified outside the editor. Reload?")
            }
    }
}
