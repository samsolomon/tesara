import SwiftUI

struct PaneHeaderView: View {
    @EnvironmentObject private var dragState: PaneDragState

    let paneID: UUID
    let title: String
    let isActive: Bool
    let theme: TerminalTheme
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(isActive ? 0.7 : 0.4))
                .lineLimit(1)

            Spacer(minLength: 0)

            CloseButton(
                foregroundColor: theme.swiftUIColor(from: theme.foreground),
                isActive: isActive,
                action: onClose
            )
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(theme.swiftUIColor(from: theme.background))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
        }
        .onDrag {
            dragState.dragStarted(sourceID: paneID)
            return NSItemProvider(object: "tesara-pane:\(paneID.uuidString)" as NSString)
        }
    }
}

private struct CloseButton: View {
    let foregroundColor: Color
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(foregroundColor.opacity(isHovered ? 0.9 : (isActive ? 0.5 : 0.3)))
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(foregroundColor.opacity(isHovered ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
