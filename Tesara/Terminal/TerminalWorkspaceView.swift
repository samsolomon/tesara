import SwiftUI

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var blockStore: BlockStore
    @StateObject private var session = TerminalSession()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalWebView(
                theme: settingsStore.activeTheme,
                fontFamily: settingsStore.settings.fontFamily,
                fontSize: settingsStore.settings.fontSize,
                transcript: session.transcript,
                onInput: session.send(text:),
                onResize: session.resize(cols:rows:)
            )
            Divider()
            footerBar
        }
        .background(settingsStore.activeTheme.swiftUIColor(from: settingsStore.activeTheme.background))
        .task {
            session.configure(blockStore: blockStore)
            if session.status == .idle {
                session.start(
                    shellPath: settingsStore.settings.shellPath,
                    workingDirectory: settingsStore.settings.defaultWorkingDirectory
                )
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Local Shell")
                    .font(.headline)
                Text(sessionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let launchError = session.launchError {
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

            Label("\(session.capturedBlockCount) captured", systemImage: "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Restart") {
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
        switch session.status {
        case .idle:
            "Ready to launch"
        case .starting:
            "Starting shell"
        case .running:
            "PTY-backed shell with xterm.js, OSC 133 parsing, and block capture"
        case .failed:
            "Launch failed"
        case .stopped:
            "Stopped"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle, .stopped:
            .gray
        case .starting:
            .orange
        case .running:
            .green
        case .failed:
            .red
        }
    }

}

#Preview {
    TerminalWorkspaceView()
        .environmentObject(SettingsStore())
}
