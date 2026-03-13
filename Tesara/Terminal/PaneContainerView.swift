import SwiftUI

struct PaneContainerView: View {
    let node: PaneNode
    let theme: TerminalTheme
    let activePaneID: UUID?
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
                onSelectPane: onSelectPane
            )

        case .split(let splitID, let direction, let first, let second, let ratio):
            GeometryReader { geometry in
                splitContent(
                    splitID: splitID,
                    direction: direction,
                    first: first,
                    second: second,
                    ratio: ratio,
                    totalSize: direction == .horizontal ? geometry.size.width : geometry.size.height
                )
            }
        }
    }

    @ViewBuilder
    private func splitContent(splitID: UUID, direction: PaneNode.SplitDirection, first: PaneNode, second: PaneNode, ratio: CGFloat, totalSize: CGFloat) -> some View {
        let firstChild = PaneContainerView(
            node: first, theme: theme,
            activePaneID: activePaneID,
            onSelectPane: onSelectPane, onUpdateRatio: onUpdateRatio,
            isSplit: true
        )
        let secondChild = PaneContainerView(
            node: second, theme: theme,
            activePaneID: activePaneID,
            onSelectPane: onSelectPane, onUpdateRatio: onUpdateRatio,
            isSplit: true
        )
        let divider = PaneDividerView(
            direction: direction,
            initialRatio: ratio,
            totalSize: totalSize,
            onUpdateRatio: { newRatio in onUpdateRatio(splitID, newRatio) }
        )

        if direction == .horizontal {
            HStack(spacing: 0) {
                firstChild.frame(width: totalSize * ratio)
                divider
                secondChild
            }
        } else {
            VStack(spacing: 0) {
                firstChild.frame(height: totalSize * ratio)
                divider
                secondChild
            }
        }
    }
}

private struct TerminalPaneLeafView: View {
    let id: UUID
    @ObservedObject var session: TerminalSession
    let isActive: Bool
    let showBorder: Bool
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
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPane(id)
        }
    }
}
