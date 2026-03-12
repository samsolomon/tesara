import SwiftUI

struct TitleBarTabStrip: View {
    @ObservedObject var manager: WorkspaceManager
    let onNewTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(manager.tabs) { tab in
                    let index = manager.tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
                    tabCapsule(tab, index: index)
                }

                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private func tabCapsule(_ tab: WorkspaceManager.Tab, index: Int) -> some View {
        let isActive = tab.id == manager.activeTabID

        return TabCapsuleButton(
            title: tab.title,
            shortcutLabel: index < 9 ? "⌘\(index + 1)" : nil,
            isActive: isActive,
            onSelect: { manager.selectTab(id: tab.id) },
            onClose: { manager.closeTab(id: tab.id) }
        )
    }
}

private struct TabCapsuleButton: View {
    let title: String
    let shortcutLabel: String?
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    if let shortcutLabel, !isHovering {
                        Text(shortcutLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
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
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
