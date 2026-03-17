import SwiftUI

private let dividerColor = Color.gray.opacity(0.3)

struct TitleBarTabStrip: View {
    @ObservedObject var manager: WorkspaceManager
    let theme: TerminalTheme

    private var foregroundColor: Color {
        theme.swiftUIColor(from: theme.foreground)
    }

    private var backgroundColor: Color {
        theme.swiftUIColor(from: theme.background)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(manager.tabs.enumerated()), id: \.element.id) { index, tab in
                let isActive = tab.id == manager.activeTabID
                let nextIsActive = index + 1 < manager.tabs.count && manager.tabs[index + 1].id == manager.activeTabID

                TabSegmentButton(
                    title: tab.title,
                    shortcutLabel: index < 9 ? "⌘\(index + 1)" : nil,
                    isActive: isActive,
                    foregroundColor: foregroundColor,
                    onSelect: { manager.selectTab(id: tab.id) },
                    onClose: { manager.closeTab(id: tab.id) }
                )
                .frame(maxWidth: .infinity)

                // Vertical divider between tabs, hidden adjacent to active tab
                if index < manager.tabs.count - 1 {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 1, height: 14)
                        .opacity(isActive || nextIsActive ? 0 : 1)
                }
            }
        }
        .frame(height: 24)
        .background(backgroundColor)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
    }
}

private struct TabSegmentButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let shortcutLabel: String?
    let isActive: Bool
    let foregroundColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    private var titleOpacity: Double {
        isActive ? 0.7 : 0.4
    }

    private var animation: Animation {
        reduceMotion ? .linear(duration: 0.01) : .snappy(duration: 0.18, extraBounce: 0)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(foregroundColor.opacity(titleOpacity))
                        .lineLimit(1)

                    if let shortcutLabel {
                        Text(shortcutLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(foregroundColor.opacity(0.3))
                            .opacity(isHovering ? 0 : 1)
                    }
                }

                Spacer(minLength: 0)

                CloseButton(foregroundColor: foregroundColor, isActive: true, action: onClose)
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
                    .frame(width: 20)
                    .accessibilityLabel("Close tab")
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(animation, value: isHovering)
        .animation(animation, value: isActive)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(title)
        .accessibilityHint("Select tab")
    }
}

