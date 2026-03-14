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
    @Published private(set) var shellTitle: String?
    @Published private(set) var surfaceView: GhosttySurfaceView?
    @Published private(set) var isAtPrompt = false

    /// Not `@Published` — view updates are driven by `isAtPrompt` which always
    /// changes in the same call path as `inputBarState` mutations.
    private(set) var inputBarState: InputBarState?

    private var blockStore: BlockStore?
    private var activeSessionID: UUID?
    private var activeCapture: TerminalBlockCapture?
    private var blockOrderIndex = 0

    /// Temporary files created for shell integration, cleaned up on stop/deinit.
    private var temporaryURLs: [URL] = []

    /// Unique session identifier passed to shell integration scripts for command capture.
    private(set) var shellSessionID: String = UUID().uuidString

    init() {}

#if DEBUG
    var onSendTextForTesting: ((String) -> Void)?

    func setStatusForTesting(_ status: Status) {
        self.status = status
    }
#endif

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
        currentWorkingDirectory = workingDirectory.path
        shellTitle = nil
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
#if DEBUG
        onSendTextForTesting?(text)
#endif
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
        isAtPrompt = false
        teardownInputBar()
        cleanupTemporaryFiles()

        if status != .failed {
            status = .stopped
        }
    }

    // MARK: - Input Bar

    func sendFromInputBar(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAtPrompt = false
        if trimmed.contains("\n") {
            send(text: "\u{1b}[200~" + trimmed + "\u{1b}[201~\n")
        } else {
            send(command: trimmed)
        }
    }

    func dismissInputBar() {
        isAtPrompt = false
    }

    func setupInputBar(theme: TerminalTheme, fontFamily: String, fontSize: Double) {
        guard inputBarState == nil else { return }
        let state = InputBarState()
        state.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize)
        state.keyHandler.terminalSession = self
        state.keyHandler.onClear = { [weak state] in state?.clear() }
        state.keyHandler.onDismiss = { [weak self] in self?.dismissInputBar() }
        inputBarState = state
    }

    private func teardownInputBar() {
        inputBarState?.editorView?.pauseDisplayLink()
        inputBarState = nil
    }

    // MARK: - Action Handlers

    func updateWorkingDirectory(_ url: URL) {
        let path = url.path
        guard path != currentWorkingDirectory else { return }
        currentWorkingDirectory = path
    }

    func updateTitle(_ title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = normalized.isEmpty ? nil : normalized
        guard shellTitle != nextTitle else { return }
        shellTitle = nextTitle
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
        isAtPrompt = true
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
        isAtPrompt = false
        teardownInputBar()
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

        blockStore?.recordBlock(sessionID: activeSessionID, block: activeCapture, orderIndex: blockOrderIndex)
        blockOrderIndex += 1
        capturedBlockCount = blockOrderIndex
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

    // MARK: - Stale Temp File Cleanup

    /// Removes Tesara temp files older than the given threshold (default 24 hours).
    /// Safe to call on launch — only deletes stale files, not those from running instances.
    static func cleanupStaleTempFiles(olderThan threshold: TimeInterval = 86400) {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-threshold)
        guard let contents = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        let prefixes = ["tesara-cmd-", "tesara-zsh-", "tesara-bash-", "tesara-fish-"]
        for entry in contents where prefixes.contains(where: { entry.hasPrefix($0) }) {
            let path = (tmpDir as NSString).appendingPathComponent(entry)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fm.removeItem(atPath: path)
        }
    }
}
