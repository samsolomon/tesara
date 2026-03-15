import SwiftUI
import UniformTypeIdentifiers

struct PaneContainerView: View {
    let node: PaneNode
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let inputBarEnabled: Bool
    let activePaneID: UUID?
    let dimInactiveSplits: Bool
    let inactiveSplitDimAmount: Double
    let tabTitleMode: TabTitleMode
    let onSelectPane: (UUID) -> Void
    let onUpdateRatio: (UUID, CGFloat) -> Void
    var onClosePane: ((UUID) -> Void)?
    var isSplit: Bool = false

    var body: some View {
        switch node {
        case .leaf(let id, let session):
            paneWithHeader(id: id, session: session) {
                TerminalPaneLeafView(
                    id: id,
                    session: session,
                    isActive: id == activePaneID,
                    showBorder: isSplit,
                    theme: theme,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    inputBarEnabled: inputBarEnabled,
                    dimInactiveSplit: dimInactiveSplits,
                    inactiveSplitDimAmount: inactiveSplitDimAmount,
                    onSelectPane: onSelectPane
                )
            }

        case .editor(let id, let editorSession):
            editorWithHeader(id: id, session: editorSession) {
                EditorPaneLeafView(
                    id: id,
                    session: editorSession,
                    isActive: id == activePaneID,
                    showBorder: isSplit,
                    theme: theme,
                    dimInactiveSplit: dimInactiveSplits,
                    inactiveSplitDimAmount: inactiveSplitDimAmount,
                    onSelectPane: onSelectPane
                )
            }

        case .split(let splitID, let direction, let first, let second, let ratio):
            splitContent(
                splitID: splitID,
                direction: direction,
                first: first,
                second: second,
                ratio: ratio
            )
        }
    }

    @ViewBuilder
    private func paneWithHeader<Content: View>(id: UUID, session: TerminalSession, @ViewBuilder content: () -> Content) -> some View {
        if isSplit {
            PaneDropTarget(paneID: id) {
                VStack(spacing: 0) {
                    PaneHeaderView(
                        paneID: id,
                        title: WorkspaceManager.paneTitle(
                            shellTitle: session.shellTitle,
                            workingDirectory: session.currentWorkingDirectory,
                            mode: tabTitleMode
                        ),
                        isActive: id == activePaneID,
                        theme: theme,
                        onClose: { onClosePane?(id) }
                    )
                    content()
                        .layoutPriority(1)
                }
            }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func editorWithHeader<Content: View>(id: UUID, session: EditorSession, @ViewBuilder content: () -> Content) -> some View {
        if isSplit {
            PaneDropTarget(paneID: id) {
                VStack(spacing: 0) {
                    PaneHeaderView(
                        paneID: id,
                        title: session.displayTitle,
                        isActive: id == activePaneID,
                        theme: theme,
                        onClose: { onClosePane?(id) }
                    )
                    content()
                        .layoutPriority(1)
                }
            }
        } else {
            content()
        }
    }

    private func splitContent(
        splitID: UUID,
        direction: PaneNode.SplitDirection,
        first: PaneNode,
        second: PaneNode,
        ratio: CGFloat
    ) -> some View {
        PaneSplitView(
            direction: direction,
            ratio: ratio,
            onUpdateRatio: { newRatio in onUpdateRatio(splitID, newRatio) },
            first: {
                PaneContainerView(
                    node: first,
                    theme: theme,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    inputBarEnabled: inputBarEnabled,
                    activePaneID: activePaneID,
                    dimInactiveSplits: dimInactiveSplits,
                    inactiveSplitDimAmount: inactiveSplitDimAmount,
                    tabTitleMode: tabTitleMode,
                    onSelectPane: onSelectPane,
                    onUpdateRatio: onUpdateRatio,
                    onClosePane: onClosePane,
                    isSplit: true
                )
            },
            second: {
                PaneContainerView(
                    node: second,
                    theme: theme,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    inputBarEnabled: inputBarEnabled,
                    activePaneID: activePaneID,
                    dimInactiveSplits: dimInactiveSplits,
                    inactiveSplitDimAmount: inactiveSplitDimAmount,
                    tabTitleMode: tabTitleMode,
                    onSelectPane: onSelectPane,
                    onUpdateRatio: onUpdateRatio,
                    onClosePane: onClosePane,
                    isSplit: true
                )
            }
        )
    }
}

private struct PaneDropTarget<Content: View>: View {
    @EnvironmentObject private var dragState: PaneDragState

    let paneID: UUID
    @ViewBuilder let content: Content
    @State private var isDropTargeted = false

    private var showOverlay: Bool {
        isDropTargeted && dragState.activeDragSourceID != nil
    }

    var body: some View {
        content
            .overlay {
                Group {
                    if showOverlay {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: showOverlay)
            }
            .onDrop(of: [.plainText], isTargeted: $isDropTargeted) { _ in
                guard dragState.activeDragSourceID != nil else { return false }
                dragState.dropPerformed()
                return true
            }
            .onChange(of: isDropTargeted) { _, isTargeted in
                if isTargeted {
                    dragState.targetEntered(paneID)
                } else {
                    dragState.targetExited(paneID)
                }
            }
    }
}

private struct EditorPaneLeafView: View {
    let id: UUID
    @ObservedObject var session: EditorSession
    let isActive: Bool
    let showBorder: Bool
    let theme: TerminalTheme
    let dimInactiveSplit: Bool
    let inactiveSplitDimAmount: Double
    let onSelectPane: (UUID) -> Void

    var body: some View {
        Group {
            if let editorView = session.editorView as? EditorView {
                GeometryReader { geo in
                    EditorViewRepresentable(editorView: editorView)
                        .onAppear {
                            #if DEBUG
                            LocalLogStore.shared.log("[EditorPane] pane=\(id.uuidString) size=\(Int(geo.size.width))x\(Int(geo.size.height))")
                            #endif
                            editorView.setFrameSize(geo.size)
                            editorView.sizeDidChange(geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            #if DEBUG
                            LocalLogStore.shared.log("[EditorPane] pane=\(id.uuidString) size=\(Int(newSize.width))x\(Int(newSize.height))")
                            #endif
                            editorView.setFrameSize(newSize)
                            editorView.sizeDidChange(newSize)
                        }
                }
                .id(session.id)
            } else {
                Color.clear
            }
        }
        .overlay {
            if showBorder, dimInactiveSplit, !isActive {
                Rectangle()
                    .fill(theme.swiftUIColor(from: theme.background).opacity(inactiveSplitDimAmount))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPane(id)
        }
    }
}

private struct TerminalPaneLeafView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    let id: UUID
    @ObservedObject var session: TerminalSession
    let isActive: Bool
    let showBorder: Bool
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let inputBarEnabled: Bool
    let dimInactiveSplit: Bool
    let inactiveSplitDimAmount: Double
    let onSelectPane: (UUID) -> Void

    private var showInputBar: Bool {
        inputBarEnabled && !session.isAlternateScreen && session.inputBarState?.editorView != nil
    }

    @ViewBuilder
    private func terminalSurface(_ surfaceView: GhosttySurfaceView) -> some View {
        GeometryReader { geo in
            GhosttySurfaceRepresentable(surfaceView: surfaceView)
                .onAppear {
                    #if DEBUG
                    LocalLogStore.shared.log("[TerminalPane] pane=\(id.uuidString) size=\(Int(geo.size.width))x\(Int(geo.size.height))")
                    #endif
                    surfaceView.setFrameSize(geo.size)
                    surfaceView.sizeDidChange(geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    #if DEBUG
                    LocalLogStore.shared.log("[TerminalPane] pane=\(id.uuidString) size=\(Int(newSize.width))x\(Int(newSize.height))")
                    #endif
                    surfaceView.setFrameSize(newSize)
                    surfaceView.sizeDidChange(newSize)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func inputBarRegion(_ inputBarState: InputBarState, session: TerminalSession, surfaceView: GhosttySurfaceView) -> some View {
        VStack(spacing: 4) {
            if session.isHistorySearchActive {
                HistorySearchOverlayView(
                    historyController: inputBarState.historyController,
                    theme: theme,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    onAccept: {
                        inputBarState.historyController.acceptSearchResult(inputBarState: inputBarState)
                        focusInputBar(session: session, surfaceView: surfaceView)
                    },
                    onCancel: {
                        inputBarState.historyController.cancelSearch()
                        focusInputBar(session: session, surfaceView: surfaceView)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            InputBarView(
                inputBarState: inputBarState,
                theme: theme,
                fontFamily: fontFamily,
                fontSize: fontSize
            )
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            focusInputBar(session: session, surfaceView: surfaceView)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusInputBar(session: session, surfaceView: surfaceView)
        }
    }

    private func syncInputBarPresentation(session: TerminalSession, surfaceView: GhosttySurfaceView) {
        guard isActive else {
            session.inputBarState?.editorView?.focusDidChange(false)
            session.inputBarState?.editorView?.renderOneFrame()
            session.inputBarState?.editorView?.pauseDisplayLink()
            surfaceView.keyboardFocusDisabled = false
            surfaceView.focusDidChange(false)
            return
        }

        if inputBarEnabled && !session.isAlternateScreen {
            // Ensure the input bar editor exists and always owns keyboard focus
            let s = settingsStore.settings
            let cursorCfg = s.cursorStyle.editorCursorConfig(color: hexToColorU8(settingsStore.activeTheme.cursor))
            session.setupInputBar(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorCfg, cursorBlink: true)
            session.inputBarState?.editorView?.resumeDisplayLink()
            surfaceView.keyboardFocusDisabled = true
            surfaceView.setTerminalCursorHidden(true)
            focusInputBar(session: session, surfaceView: surfaceView)
        } else {
            // No input bar: terminal owns keyboard focus
            surfaceView.keyboardFocusDisabled = false
            surfaceView.setTerminalCursorHidden(false)
            if let window = surfaceView.window {
                window.makeFirstResponder(surfaceView)
                surfaceView.focusDidChange(true)
            }
        }
    }

    private func focusInputBar(session: TerminalSession, surfaceView: GhosttySurfaceView) {
        Task { @MainActor in
            var editorView = session.inputBarState?.editorView

            for _ in 0..<8 {
                guard let currentEditorView = editorView else { return }

                if let window = currentEditorView.window {
                    // Force-unfocus the terminal surface so Ghostty hides its cursor.
                    // focusDidChange guards on self.focused, but on first launch focused
                    // may already be false — call the Ghostty API directly.
                    surfaceView.setGhosttyFocus(false)
                    if window.firstResponder === currentEditorView || window.makeFirstResponder(currentEditorView) {
                        currentEditorView.focusDidChange(true)
                        return
                    }
                    currentEditorView.focusDidChange(false)
                }

                try? await Task.sleep(for: .milliseconds(50))
                editorView = session.inputBarState?.editorView
            }

            session.inputBarState?.editorView?.focusDidChange(false)
        }
    }

    var body: some View {
        Group {
            if let surfaceView = session.surfaceView {
                VStack(spacing: 0) {
                    terminalSurface(surfaceView)
                        .layoutPriority(1)

                    if showInputBar, let inputBarState = session.inputBarState {
                        inputBarRegion(inputBarState, session: session, surfaceView: surfaceView)
                    }
                }
                .id(session.id)
                .onAppear {
                    syncInputBarPresentation(session: session, surfaceView: surfaceView)
                }
                .onChange(of: isActive) { _, _ in
                    syncInputBarPresentation(session: session, surfaceView: surfaceView)
                }
                .onChange(of: session.isAtPrompt) { _, _ in
                    syncInputBarPresentation(session: session, surfaceView: surfaceView)
                }
                .onChange(of: inputBarEnabled) { _, _ in
                    syncInputBarPresentation(session: session, surfaceView: surfaceView)
                }
                .onChange(of: session.isAlternateScreen) { _, _ in
                    syncInputBarPresentation(session: session, surfaceView: surfaceView)
                }
            } else {
                Color.clear
            }
        }
        .overlay {
            if showBorder, dimInactiveSplit, !isActive {
                Rectangle()
                    .fill(theme.swiftUIColor(from: theme.background).opacity(inactiveSplitDimAmount))
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPane(id)
        }
    }
}
