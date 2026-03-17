import SwiftUI

struct PaneHeaderView: View {
    @EnvironmentObject private var dragState: PaneDragState

    let paneID: UUID
    let title: String
    let isActive: Bool
    let hasNotification: Bool
    let theme: TerminalTheme
    let onClose: () -> Void

    @State private var isHovered = false

    private var isDragSource: Bool {
        dragState.activeDragSourceID == paneID
    }

    var body: some View {
        HStack(spacing: 0) {
            NotificationDot()
                .padding(.trailing, 4)
                .visible(hasNotification && !isActive)

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
            .opacity(isHovered && !isDragSource ? 1 : 0)
            .allowsHitTesting(isHovered && !isDragSource)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
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
        .opacity(isDragSource ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.15), value: isDragSource)
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            dragState.dragStarted(sourceID: paneID)
            return NSItemProvider(object: "tesara-pane:\(paneID.uuidString)" as NSString)
        }
    }
}

struct NotificationDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
            .transition(.scale.combined(with: .opacity))
    }
}

extension View {
    @ViewBuilder
    func visible(_ condition: Bool) -> some View {
        if condition {
            self
        }
    }
}

struct CloseButton: View {
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
