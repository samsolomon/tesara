import Foundation

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    enum Status: String {
        case idle
        case starting
        case running
        case failed
        case stopped
    }

    let id = UUID()

    @Published private(set) var status: Status = .idle
    @Published private(set) var launchError: String?
    @Published private(set) var capturedBlockCount = 0
    @Published private(set) var currentWorkingDirectory: String?
    @Published private(set) var surfaceView: GhosttySurfaceView?

    private var blockStore: BlockStore?
    private var activeSessionID: UUID?
    private var activeCapture: TerminalBlockCapture?
    private var blockOrderIndex = 0

    /// Temporary files created for shell integration, cleaned up on stop/deinit.
    private var temporaryURLs: [URL] = []

    /// Unique session identifier passed to shell integration scripts for command capture.
    private(set) var shellSessionID: String = UUID().uuidString

    init() {}

    func configure(blockStore: BlockStore) {
        if self.blockStore == nil {
            self.blockStore = blockStore
        }
    }

    // MARK: - Start

    func start(shellPath: String, workingDirectory: URL) {
        guard surfaceView == nil else { return }

        status = .starting
        launchError = nil
        capturedBlockCount = 0
        blockOrderIndex = 0
        activeCapture = nil
        activeSessionID = blockStore?.startSession(shellPath: shellPath, workingDirectory: workingDirectory)

        guard let app = GhosttyApp.shared.app else {
            status = .failed
            launchError = "Ghostty app not initialized"
            return
        }

        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: shellPath,
            workingDirectory: workingDirectory,
            sessionID: shellSessionID
        )
        temporaryURLs = config.temporaryURLs

        let view = GhosttySurfaceView(app: app, config: config)
        view.session = self
        view.registerWithApp()
        surfaceView = view

        status = .running
    }

    // MARK: - Send

    func send(command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(text: trimmed + "\n")
    }

    func send(text: String) {
        guard !text.isEmpty else { return }
        guard let surface = surfaceView?.surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    // MARK: - Stop

    func stop() {
        if let surface = surfaceView?.surface {
            ghostty_surface_request_close(surface)
        }
        surfaceView = nil
        cleanupTemporaryFiles()

        if status != .failed {
            status = .stopped
        }
    }

    // MARK: - Action Handlers

    func updateWorkingDirectory(_ url: URL) {
        let path = url.path
        guard path != currentWorkingDirectory else { return }
        currentWorkingDirectory = path
    }

    func updateTitle(_ title: String) {
        // Title display will be wired in future work
    }

    func handleCommandFinished(exitCode: Int16, durationNs: UInt64) {
        let code = exitCode == -1 ? nil : Int(exitCode)

        let commandText = readAndCleanupCommandFile()
        if let commandText, !commandText.isEmpty {
            var capture = TerminalBlockCapture(
                startedAt: Date(timeIntervalSinceNow: -Double(durationNs) / 1_000_000_000),
                finishedAt: Date(),
                stage: .output
            )
            capture.commandText = commandText
            capture.exitCode = code
            activeCapture = capture
        }

        finalizeActiveCaptureIfNeeded(exitCode: code)
    }

    /// Reads and removes the shell-side command temp file for this session.
    func readAndCleanupCommandFile() -> String? {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(shellSessionID).txt"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        try? FileManager.default.removeItem(atPath: path)
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func handleChildExited(exitCode: UInt32) {
        surfaceView = nil
        cleanupTemporaryFiles()
        finalizeActiveCaptureIfNeeded(exitCode: Int(exitCode))
        status = .stopped
    }

    func handleSurfaceClosed() {
        stop()
    }

    // MARK: - Helpers

    private func finalizeActiveCaptureIfNeeded(exitCode: Int?) {
        guard var activeCapture, let activeSessionID else { return }

        activeCapture.finishedAt = Date()
        activeCapture.exitCode = exitCode
        activeCapture.commandText = sanitizeCommand(activeCapture.commandText)
        activeCapture.outputText = activeCapture.outputText.trimmingCharacters(in: .newlines)

        guard !activeCapture.commandText.isEmpty else {
            self.activeCapture = nil
            return
        }

        let didPersist = blockStore?.recordBlock(sessionID: activeSessionID, block: activeCapture, orderIndex: blockOrderIndex) ?? false
        if didPersist {
            blockOrderIndex += 1
            capturedBlockCount = blockOrderIndex
        }
        self.activeCapture = nil
    }

    private func sanitizeCommand(_ command: String) -> String {
        command
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupTemporaryFiles() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }
}
