import SwiftUI

struct TerminalWorkspaceView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var session = TerminalSession()
    @State private var commandText = "pwd"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalWebView(theme: settingsStore.activeTheme, lines: session.lines)
            Divider()
            commandBar
        }
        .background(settingsStore.activeTheme.swiftUIColor(from: settingsStore.activeTheme.background))
        .task {
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

    private var commandBar: some View {
        HStack(spacing: 12) {
            TextField("Run a shell command", text: $commandText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendCommand)

            Button("Send", action: sendCommand)
                .keyboardShortcut(.return, modifiers: [.command])

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
            "PTY-backed shell live; xterm.js renderer still to come"
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

    private func sendCommand() {
        let command = commandText
        session.send(command: command)
        commandText = ""
    }
}

#Preview {
    TerminalWorkspaceView()
        .environmentObject(SettingsStore())
}
