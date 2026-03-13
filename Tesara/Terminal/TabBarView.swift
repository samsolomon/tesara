import SwiftUI

struct TitleBarTabStrip: View {
    @Environment(\.controlActiveState) private var controlActiveState

    @ObservedObject var manager: WorkspaceManager
    let isDarkBackground: Bool
    let onNewTab: () -> Void

    @State private var isHoveringNewTab = false

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

            Rectangle()
                .fill((isDarkBackground ? Color.white : Color.black).opacity(controlActiveState == .key ? 0.06 : 0.04))
                .frame(width: 1, height: 22)
                .padding(.horizontal, 4)

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDarkBackground ? .white.opacity(0.5) : .black.opacity(0.4))
            .overlay {
                if isHoveringNewTab {
                    Circle()
                        .strokeBorder(strokeColor, lineWidth: 1)
                        .frame(width: 24, height: 24)
                }
            }
            .animation(.snappy(duration: 0.2), value: isHoveringNewTab)
            .onHover { hovering in
                isHoveringNewTab = hovering
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
            isDarkBackground: isDarkBackground,
            onSelect: { manager.selectTab(id: tab.id) },
            onClose: { manager.closeTab(id: tab.id) }
        )
    }
}

private struct TabCapsuleButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    let title: String
    let shortcutLabel: String?
    let isActive: Bool
    let isDarkBackground: Bool
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

    private var inactiveHoverStroke: Color {
        primaryColor.opacity(isHovering ? 0.16 : 0.08)
    }

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
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)

                    if let shortcutLabel {
                        Text(shortcutLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(secondaryColor)
                            .opacity(isHovering ? 0 : 1)
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
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(.clear)
                .overlay {
                    if isActive {
                        activeBackground
                    } else if isHovering {
                        Capsule()
                            .strokeBorder(inactiveHoverStroke, lineWidth: 1)
                    }
                }
        }
        .clipShape(Capsule())
        .animation(animation, value: isHovering)
        .animation(animation, value: isActive)
        .animation(animation, value: controlActiveState)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
        .accessibilityHint("Select tab")
    }

    @ViewBuilder
    private var activeBackground: some View {
        if #available(macOS 26, *) {
            Capsule()
                .fill(.regularMaterial.opacity(activeFillOpacity))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(isDarkBackground ? activeStrokeOpacity : 0.08), lineWidth: 0.5)
                }
                .glassEffect(.regular, in: .capsule)
        } else {
            Capsule()
                .fill(.ultraThinMaterial.opacity(activeFillOpacity))
                .overlay {
                    Capsule()
                        .strokeBorder(primaryColor.opacity(activeStrokeOpacity), lineWidth: 0.5)
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
