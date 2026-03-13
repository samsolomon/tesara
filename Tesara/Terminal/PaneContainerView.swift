import SwiftUI

struct PaneContainerView: View {
    private let dividerThickness: CGFloat = 4

    let node: PaneNode
    let theme: TerminalTheme
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
            GeometryReader { geometry in
                let containerSize = geometry.size
                let mainAxisSize = max(
                    (direction == .horizontal ? containerSize.width : containerSize.height) - dividerThickness,
                    1
                )
                splitContent(
                    splitID: splitID,
                    direction: direction,
                    first: first,
                    second: second,
                    ratio: ratio,
                    containerSize: containerSize,
                    mainAxisSize: mainAxisSize
                )
            }
        }
    }

    @ViewBuilder
    private func splitContent(
        splitID: UUID,
        direction: PaneNode.SplitDirection,
        first: PaneNode,
        second: PaneNode,
        ratio: CGFloat,
        containerSize: CGSize,
        mainAxisSize: CGFloat
    ) -> some View {
        let firstChild = PaneContainerView(
            node: first, theme: theme,
            activePaneID: activePaneID,
            dimInactiveSplits: dimInactiveSplits,
            inactiveSplitDimAmount: inactiveSplitDimAmount,
            onSelectPane: onSelectPane, onUpdateRatio: onUpdateRatio,
            isSplit: true
        )
        let secondChild = PaneContainerView(
            node: second, theme: theme,
            activePaneID: activePaneID,
            dimInactiveSplits: dimInactiveSplits,
            inactiveSplitDimAmount: inactiveSplitDimAmount,
            onSelectPane: onSelectPane, onUpdateRatio: onUpdateRatio,
            isSplit: true
        )
        let divider = PaneDividerView(
            direction: direction,
            initialRatio: ratio,
            totalSize: mainAxisSize,
            onUpdateRatio: { newRatio in onUpdateRatio(splitID, newRatio) }
        )
        let firstPaneSize = max(0, min(mainAxisSize * ratio, mainAxisSize))
        let secondPaneSize = max(0, mainAxisSize - firstPaneSize)

        if direction == .horizontal {
            ZStack(alignment: .topLeading) {
                firstChild
                    .frame(width: firstPaneSize, height: containerSize.height, alignment: .topLeading)
                    .clipped()
                divider
                    .frame(width: dividerThickness, height: containerSize.height)
                    .offset(x: firstPaneSize)
                secondChild
                    .frame(width: secondPaneSize, height: containerSize.height, alignment: .topLeading)
                    .offset(x: firstPaneSize + dividerThickness)
                    .clipped()
            }
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        } else {
            ZStack(alignment: .topLeading) {
                firstChild
                    .frame(width: containerSize.width, height: firstPaneSize, alignment: .topLeading)
                    .clipped()
                divider
                    .frame(width: containerSize.width, height: dividerThickness)
                    .offset(y: firstPaneSize)
                secondChild
                    .frame(width: containerSize.width, height: secondPaneSize, alignment: .topLeading)
                    .offset(y: firstPaneSize + dividerThickness)
                    .clipped()
            }
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
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
                        .onChange(of: geo.size) { _, newSize in
                            editorView.sizeDidChange(newSize)
                        }
                }
                .id(session.id)
            } else {
                Color.clear
            }
        }
        .border(showBorder && isActive ? Color.accentColor : Color.clear, width: showBorder ? 2 : 0)
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
    let id: UUID
    @ObservedObject var session: TerminalSession
    let isActive: Bool
    let showBorder: Bool
    let theme: TerminalTheme
    let dimInactiveSplit: Bool
    let inactiveSplitDimAmount: Double
    let onSelectPane: (UUID) -> Void

    var body: some View {
        Group {
            if let surfaceView = session.surfaceView {
                GeometryReader { geo in
                    GhosttySurfaceRepresentable(surfaceView: surfaceView)
                        .onChange(of: geo.size) { _, newSize in
                            surfaceView.sizeDidChange(newSize)
                        }
                }
                .id(session.id)
            } else {
                Color.clear
            }
        }
        .border(showBorder && isActive ? Color.accentColor : Color.clear, width: showBorder ? 2 : 0)
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
