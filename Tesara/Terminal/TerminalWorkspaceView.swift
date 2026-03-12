import SwiftUI

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @ObservedObject var manager: WorkspaceManager

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(manager: manager, onNewTab: addTab)
            Divider()
            header
            Divider()
            terminalContent
            Divider()
            footerBar
        }
        .background(settingsStore.activeTheme.swiftUIColor(from: settingsStore.activeTheme.background))
        .task {
            if manager.tabs.isEmpty {
                addTab()
            }
        }
    }

    private func addTab() {
        manager.newTab(
            shellPath: settingsStore.settings.shellPath,
            workingDirectory: settingsStore.settings.defaultWorkingDirectory,
            blockStore: blockStore
        )
    }

    private var terminalContent: some View {
        ZStack {
            ForEach(manager.tabs) { tab in
                PaneContainerView(
                    node: tab.rootPane,
                    theme: settingsStore.activeTheme,
                    fontFamily: settingsStore.settings.fontFamily,
                    fontSize: settingsStore.settings.fontSize,
                    activePaneID: manager.activePaneID,
                    onSelectPane: { paneID in
                        manager.selectPane(id: paneID)
                    },
                    onUpdateRatio: { splitID, ratio in
                        manager.updatePaneRatio(splitID: splitID, ratio: ratio)
                    }
                )
                .opacity(tab.id == manager.activeTabID ? 1 : 0)
                .allowsHitTesting(tab.id == manager.activeTabID)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.activeSession?.currentWorkingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Local Shell")
                    .font(.headline)
                Text(sessionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let launchError = manager.activeSession?.launchError {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footerBar: some View {
        HStack(spacing: 12) {
            Label("Type directly in the terminal surface", systemImage: "keyboard")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Label("\(manager.activeSession?.capturedBlockCount ?? 0) captured", systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Restart") {
                guard let session = manager.activeSession else { return }
                session.stop()
                session.start(
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory
                )
            }
        }
        .padding(16)
    }

    private var sessionSubtitle: String {
        guard let status = manager.activeSession?.status else { return "No active session" }
        switch status {
        case .idle:
            return "Ready to launch"
        case .starting:
            return "Starting shell"
        case .running:
            return "PTY-backed shell with xterm.js, OSC 133 parsing, and block capture"
        case .failed:
            return "Launch failed"
        case .stopped:
            return "Stopped"
        }
    }

    private var statusColor: Color {
        guard let status = manager.activeSession?.status else { return .gray }
        switch status {
        case .idle, .stopped:
            return .gray
        case .starting:
            return .orange
        case .running:
            return .green
        case .failed:
            return .red
        }
    }
}
