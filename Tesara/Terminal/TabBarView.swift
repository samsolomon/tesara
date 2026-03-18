import SwiftUI

struct TitleBarTabStrip: View {
    @Environment(\.controlActiveState) private var controlActiveState

    @ObservedObject var manager: WorkspaceManager
    let isDarkBackground: Bool

    private var strokeColor: Color {
        (isDarkBackground ? Color.white : Color.black).opacity(0.2)
    }

    private var containerFill: Color {
        let base = isDarkBackground ? Color.white : Color.black
        let opacity = controlActiveState == .key ? (isDarkBackground ? 0.075 : 0.055) : (isDarkBackground ? 0.055 : 0.04)
        return base.opacity(opacity)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(manager.tabs.enumerated()), id: \.element.id) { index, tab in
                tabCapsule(tab, index: index)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(containerFill)
        }
    }

    private func tabCapsule(_ tab: WorkspaceManager.Tab, index: Int) -> some View {
        let isActive = tab.id == manager.activeTabID

        return TabCapsuleButton(
            title: tab.title,
            shortcutLabel: index < 9 ? "⌘\(index + 1)" : nil,
            isActive: isActive,
            hasNotification: manager.tabsWithNotifications.contains(tab.id),
            isDarkBackground: isDarkBackground,
            onSelect: { manager.selectTab(id: tab.id) },
            onClose: { manager.closeTab(id: tab.id) }
        )
    }
}

struct TabCapsuleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    let title: String
    let shortcutLabel: String?
    let isActive: Bool
    let hasNotification: Bool
    let isDarkBackground: Bool
    var useRoundedRect: Bool = false
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isHoveringCloseButton = false

    private var primaryColor: Color {
        let base = isDarkBackground ? Color.white : Color.black
        return base.opacity(windowIsActive ? 0.94 : 0.72)
    }

    private var secondaryColor: Color {
        primaryColor.opacity(windowIsActive ? 0.48 : 0.36)
    }

    private var windowIsActive: Bool {
        controlActiveState == .key
    }

    private var trailingSlotWidth: CGFloat {
        20
    }

    private var animation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.18, extraBounce: 0)
    }

    private var inactiveHoverFill: Color {
        let base = isDarkBackground ? Color.white : Color.black
        let opacity = windowIsActive ? (isDarkBackground ? 0.07 : 0.045) : (isDarkBackground ? 0.05 : 0.03)
        return base.opacity(opacity)
    }

    private var inactiveHoverStroke: Color {
        primaryColor.opacity(windowIsActive ? 0.08 : 0.05)
    }

    private static let rrRadius: CGFloat = 8

    private var closeButtonForeground: Color {
        primaryColor.opacity(isHoveringCloseButton ? 0.92 : 0.78)
    }

    private var activeFillOpacity: Double {
        windowIsActive ? 1 : 0.72
    }

    private var activeStrokeOpacity: Double {
        windowIsActive ? 0.12 : 0.08
    }

    var body: some View {
        Button(action: onSelect) {
            buttonContent
        }
        .buttonStyle(.plain)
        .background { buttonBackground }
        .clipShape(useRoundedRect
            ? AnyShape(RoundedRectangle(cornerRadius: Self.rrRadius, style: .continuous))
            : AnyShape(Capsule()))
        .animation(animation, value: isHovering)
        .animation(animation, value: isActive)
        .animation(animation, value: hasNotification)
        .animation(animation, value: controlActiveState)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
        .accessibilityHint("Select tab")
    }

    private var buttonContent: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                NotificationDot()
                    .visible(hasNotification && !isActive)

                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(primaryColor)
                    .lineLimit(1)

                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondaryColor)
                }
            }

            Spacer(minLength: 0)

            ZStack {
                closeButton
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
            .frame(width: trailingSlotWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(useRoundedRect
            ? AnyShape(RoundedRectangle(cornerRadius: Self.rrRadius, style: .continuous))
            : AnyShape(Capsule()))
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if isActive {
            activeBackground
        } else if isHovering {
            inactiveHoverBackground
        }
    }

    private func filledShape<S: InsettableShape, F: ShapeStyle>(
        _ shape: S, fill: F, strokeColor: Color
    ) -> some View {
        shape.fill(fill)
            .overlay { shape.strokeBorder(strokeColor, lineWidth: 0.5) }
    }

    private var rrShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.rrRadius, style: .continuous)
    }

    @ViewBuilder
    private var inactiveHoverBackground: some View {
        if useRoundedRect {
            filledShape(rrShape, fill: inactiveHoverFill, strokeColor: inactiveHoverStroke)
        } else {
            filledShape(Capsule(), fill: inactiveHoverFill, strokeColor: inactiveHoverStroke)
        }
    }

    @ViewBuilder
    private var activeBackground: some View {
        let activeStroke = isDarkBackground ? activeStrokeOpacity : 0.08
        if #available(macOS 26, *) {
            if useRoundedRect {
                filledShape(rrShape, fill: .regularMaterial.opacity(activeFillOpacity),
                            strokeColor: .white.opacity(activeStroke))
                    .glassEffect(.regular, in: .rect(cornerRadius: Self.rrRadius, style: .continuous))
            } else {
                filledShape(Capsule(), fill: .regularMaterial.opacity(activeFillOpacity),
                            strokeColor: .white.opacity(activeStroke))
                    .glassEffect(.regular, in: .capsule)
            }
        } else {
            if useRoundedRect {
                filledShape(rrShape, fill: .ultraThinMaterial.opacity(activeFillOpacity),
                            strokeColor: primaryColor.opacity(activeStrokeOpacity))
            } else {
                filledShape(Capsule(), fill: .ultraThinMaterial.opacity(activeFillOpacity),
                            strokeColor: primaryColor.opacity(activeStrokeOpacity))
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(closeButtonForeground)
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            if #available(macOS 26, *) {
                Circle()
                    .fill(.regularMaterial)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .opacity(isHoveringCloseButton ? 1 : 0.84)
            } else {
                Circle()
                    .fill(isDarkBackground ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
            }
        }
        .scaleEffect(isHoveringCloseButton ? 1 : 0.96)
        .onHover { hovering in
            isHoveringCloseButton = hovering
        }
        .accessibilityLabel("Close tab")
    }
}

struct TabSidebarList: View {
    @ObservedObject var manager: WorkspaceManager
    let isDarkBackground: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(Array(manager.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabCapsuleButton(
                        title: tab.title,
                        shortcutLabel: index < 9 ? "⌘\(index + 1)" : nil,
                        isActive: tab.id == manager.activeTabID,
                        hasNotification: manager.tabsWithNotifications.contains(tab.id),
                        isDarkBackground: isDarkBackground,
                        useRoundedRect: true,
                        onSelect: { manager.selectTab(id: tab.id) },
                        onClose: { manager.closeTab(id: tab.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 180)
        // Titlebar (28) + traffic-light offset (8) + gutter (2) — matches SettingsDetailContainer.topInset
        .contentMargins(.top, 38, for: .scrollContent)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1)
        }
    }
}
