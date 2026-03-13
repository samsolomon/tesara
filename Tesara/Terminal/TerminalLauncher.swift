import Foundation

/// Events emitted by a terminal process (retained for test infrastructure).
enum TerminalEvent {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

/// Handle for interacting with a running terminal process (retained for test infrastructure).
protocol TerminalProcessHandle {
    func send(_ input: String) throws
    func resize(cols: UInt16, rows: UInt16)
    func stop()
}

/// Protocol for launching terminal processes (retained for test infrastructure).
protocol TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle
}

enum TerminalLaunchError: LocalizedError {
    case invalidShellPath
    case invalidWorkingDirectory

    var errorDescription: String? {
        switch self {
        case .invalidShellPath:
            "The selected shell path is not executable."
        case .invalidWorkingDirectory:
            "The default working directory does not exist."
        }
    }
}
