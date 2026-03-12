import SwiftUI

struct TabBarView: View {
    @ObservedObject var manager: WorkspaceManager
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(manager.tabs) { tab in
                tabItem(tab)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.caption)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            Spacer()
        }
        .frame(height: 32)
        .background(.bar)
    }

    private func tabItem(_ tab: WorkspaceManager.Tab) -> some View {
        let isActive = tab.id == manager.activeTabID

        return HStack(spacing: 6) {
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)

            Button {
                manager.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.selectTab(id: tab.id)
        }
    }
}
