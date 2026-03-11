import Foundation

@MainActor
final class TerminalSession: ObservableObject {
    enum Status: String {
        case idle
        case starting
        case running
        case failed
        case stopped
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let text: String

        enum Kind: String {
            case info
            case input
            case output
            case error
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [Line] = []
    @Published private(set) var launchError: String?

    private let launcher: TerminalLaunching
    private var processHandle: TerminalProcessHandle?

    init(launcher: TerminalLaunching = PTYShellLauncher()) {
        self.launcher = launcher
    }

    func start(shellPath: String, workingDirectory: URL) {
        guard processHandle == nil else {
            return
        }

        status = .starting
        lines.removeAll()
        launchError = nil
        append(.info, "Launching \(shellPath) in \(workingDirectory.path)")

        do {
            processHandle = try launcher.launch(
                shellPath: shellPath,
                workingDirectory: workingDirectory,
                onEvent: { [weak self] event in
                    guard let self else { return }
                    Task { @MainActor in
                        self.handle(event)
                    }
                }
            )
            status = .running
        } catch {
            status = .failed
            launchError = error.localizedDescription
            append(.error, error.localizedDescription)
        }
    }

    func send(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        do {
            try processHandle?.send(trimmed + "\n")
        } catch {
            append(.error, error.localizedDescription)
        }
    }

    func stop() {
        processHandle?.stop()
        processHandle = nil
        if status != .failed {
            status = .stopped
        }
    }

    private func handle(_ event: TerminalEvent) {
        switch event {
        case .stdout(let text):
            append(.output, text)
        case .stderr(let text):
            append(.error, text)
        case .exit(let code):
            append(.info, "Shell exited with status \(code)")
            processHandle = nil
            status = .stopped
        }
    }

    private func append(_ kind: Line.Kind, _ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let splitLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        for item in splitLines {
            lines.append(Line(kind: kind, text: String(item)))
        }
    }
}
