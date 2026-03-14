import SwiftUI

struct PaneContainerView: View {
    let node: PaneNode
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let inputBarEnabled: Bool
    let activePaneID: UUID?
    let dimInactiveSplits: Bool
    let inactiveSplitDimAmount: Double
    let onSelectPane: (UUID) -> Void
    let onUpdateRatio: (UUID, CGFloat) -> Void
    var isSplit: Bool = false

    var body: some View {
        switch node {
        case .leaf(let id, let session):
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

        case .editor(let id, let editorSession):
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
                    onSelectPane: onSelectPane,
                    onUpdateRatio: onUpdateRatio,
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
                    onSelectPane: onSelectPane,
                    onUpdateRatio: onUpdateRatio,
                    isSplit: true
                )
            }
        )
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
        inputBarEnabled && session.isAtPrompt && session.inputBarState?.editorView != nil
    }

    private func syncInputBarPresentation(session: TerminalSession, surfaceView: GhosttySurfaceView) {
        guard isActive else {
            session.inputBarState?.editorView?.pauseDisplayLink()
            session.inputBarState?.editorView?.focusDidChange(false)
            surfaceView.keyboardFocusDisabled = false
            surfaceView.focusDidChange(false)
            return
        }

        if session.isAtPrompt && inputBarEnabled {
            let s = settingsStore.settings
            let cursorCfg = EditorLayoutEngine.CursorConfig(
                style: s.cursorStyle,
                barWidth: s.cursorBarWidth,
                rounded: s.cursorRounded,
                color: hexToColorU8(settingsStore.activeTheme.cursor),
                glowRadius: s.cursorGlow ? s.cursorGlowRadius : 0,
                glowOpacity: s.cursorGlow ? s.cursorGlowOpacity : 0
            )
            session.setupInputBar(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorCfg, cursorBlink: s.cursorBlink)
            session.inputBarState?.editorView?.resumeDisplayLink()
            surfaceView.keyboardFocusDisabled = true
            focusInputBar(session: session, surfaceView: surfaceView)
        } else {
            session.inputBarState?.editorView?.pauseDisplayLink()
            session.inputBarState?.editorView?.focusDidChange(false)
            surfaceView.keyboardFocusDisabled = false
            if let window = surfaceView.window {
                window.makeFirstResponder(surfaceView)
                surfaceView.focusDidChange(true)
            }
        }
    }

    private func focusInputBar(session: TerminalSession, surfaceView: GhosttySurfaceView) {
        Task { @MainActor in
            guard let editorView = session.inputBarState?.editorView else { return }
            if editorView.window == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard session.isAtPrompt, let window = editorView.window else { return }
            surfaceView.focusDidChange(false)
            window.makeFirstResponder(editorView)
            editorView.focusDidChange(true)
        }
    }

    var body: some View {
        Group {
            if let surfaceView = session.surfaceView {
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
                .id(session.id)
                .overlay(alignment: .bottom) {
                    if showInputBar, let inputBarState = session.inputBarState {
                        VStack(spacing: 4) {
                            if inputBarState.historyController.isSearchActive {
                                HistorySearchOverlayView(
                                    historyController: inputBarState.historyController,
                                    theme: theme,
                                    fontFamily: fontFamily,
                                    fontSize: fontSize,
                                    onAccept: {
                                        inputBarState.historyController.acceptSearchResult(inputBarState: inputBarState)
                                    },
                                    onCancel: {
                                        inputBarState.historyController.cancelSearch()
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
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: showInputBar)
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
