import SwiftUI

struct PaneDividerView: View {
    let direction: PaneNode.SplitDirection
    let initialRatio: CGFloat
    let totalSize: CGFloat
    let onUpdateRatio: (CGFloat) -> Void

    @State private var dragStartRatio: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(
                width: direction == .horizontal ? 4 : nil,
                height: direction == .vertical ? 4 : nil
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartRatio == nil {
                            dragStartRatio = initialRatio
                        }
                        let delta = direction == .horizontal ? value.translation.width : value.translation.height
                        guard totalSize > 0 else { return }
                        let newRatio = (dragStartRatio ?? initialRatio) + delta / totalSize
                        onUpdateRatio(newRatio)
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    switch direction {
                    case .horizontal:
                        NSCursor.resizeLeftRight.push()
                    case .vertical:
                        NSCursor.resizeUpDown.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
    }
}
