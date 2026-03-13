import SwiftUI

struct TitleBarTabStrip: View {
    @ObservedObject var manager: WorkspaceManager
    let isDarkBackground: Bool
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(manager.tabs.enumerated()), id: \.element.id) { index, tab in
                tabCapsule(tab, index: index)
                    .frame(maxWidth: .infinity)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDarkBackground ? .white.opacity(0.5) : .black.opacity(0.4))
        }
        .padding(.horizontal, 4)
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
    let title: String
    let shortcutLabel: String?
    let isActive: Bool
    let isDarkBackground: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    private var primaryColor: Color {
        isDarkBackground ? .white : .black
    }

    private var secondaryColor: Color {
        primaryColor.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(primaryColor)
                .lineLimit(1)

            if let shortcutLabel, !isHovering {
                Text(shortcutLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(secondaryColor)
            }

            Spacer(minLength: 0)

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(secondaryColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background {
            if isActive {
                if #available(macOS 26, *) {
                    Capsule()
                        .fill(.regularMaterial)
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
        }
        .overlay {
            if !isActive && isHovering {
                Capsule()
                    .strokeBorder(primaryColor.opacity(0.2), lineWidth: 1)
            }
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .animation(.snappy(duration: 0.2), value: isHovering)
        .animation(.snappy(duration: 0.2), value: isActive)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
