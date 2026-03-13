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

    enum Mode {
        case pty      // Current: PTYShellLauncher + TerminalWebView
        case ghostty  // New: GhosttySurfaceView with libghostty
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

    let id = UUID()

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [Line] = []
    @Published private(set) var transcriptLog = TranscriptLog()
    @Published private(set) var launchError: String?
    @Published private(set) var capturedBlockCount = 0
    @Published var tuiPassthroughEnabled = false
    @Published private(set) var currentWorkingDirectory: String?
    @Published private(set) var surfaceView: GhosttySurfaceView?

    private(set) var mode: Mode = .pty

    private let launcher: TerminalLaunching
    private let parser: OSC133Parsing
    private var processHandle: TerminalProcessHandle?
    private var blockStore: BlockStore?
    private var activeSessionID: UUID?
    private var activeCapture: TerminalBlockCapture?
    private var blockOrderIndex = 0

    /// Temporary files created for shell integration, cleaned up on stop/deinit.
    private var temporaryURLs: [URL] = []

    /// Unique session identifier passed to shell integration scripts for command capture.
    private(set) var shellSessionID: String = UUID().uuidString

    // Render coalescing: buffer appends and flush on a timer (PTY mode only)
    private var pendingTranscriptText = ""
    private var pendingLines: [(Line.Kind, String)] = []
    private var flushTask: Task<Void, Never>?
    private static let coalesceInterval: TimeInterval = 0.008  // 8ms ≈ 120fps cap

    init(launcher: TerminalLaunching = PTYShellLauncher(), parser: OSC133Parsing = OSC133Parser()) {
        self.launcher = launcher
        self.parser = parser
    }

    func configure(blockStore: BlockStore, mode: Mode = .pty) {
        if self.blockStore == nil {
            self.blockStore = blockStore
        }
        self.mode = mode
    }

    // MARK: - Start

    func start(shellPath: String, workingDirectory: URL) {
        switch mode {
        case .pty:
            startPTY(shellPath: shellPath, workingDirectory: workingDirectory)
        case .ghostty:
            startGhostty(shellPath: shellPath, workingDirectory: workingDirectory)
        }
    }

    /// Resets shared state for a new session start (used by both PTY and ghostty modes).
    private func resetSessionState(shellPath: String, workingDirectory: URL) {
        status = .starting
        launchError = nil
        capturedBlockCount = 0
        blockOrderIndex = 0
        activeCapture = nil
        activeSessionID = blockStore?.startSession(shellPath: shellPath, workingDirectory: workingDirectory)
    }

    private func startPTY(shellPath: String, workingDirectory: URL) {
        guard processHandle == nil else { return }

        resetSessionState(shellPath: shellPath, workingDirectory: workingDirectory)
        lines.removeAll()
        transcriptLog.reset()
        parser.reset()
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

    private func startGhostty(shellPath: String, workingDirectory: URL) {
        guard surfaceView == nil, let app = GhosttyApp.shared.app else {
            status = .failed
            launchError = "Ghostty app not initialized"
            return
        }

        resetSessionState(shellPath: shellPath, workingDirectory: workingDirectory)

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

        switch mode {
        case .pty:
            do {
                try processHandle?.send(text)
            } catch {
                append(.error, error.localizedDescription)
            }
        case .ghostty:
            guard let surface = surfaceView?.surface else { return }
            text.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
            }
        }
    }

    // MARK: - Stop

    func stop() {
        switch mode {
        case .pty:
            flushPendingOutput()
            processHandle?.stop()
            processHandle = nil
        case .ghostty:
            if let surface = surfaceView?.surface {
                ghostty_surface_request_close(surface)
            }
            surfaceView = nil
            cleanupTemporaryFiles()
        }

        if status != .failed {
            status = .stopped
        }
    }

    // MARK: - Resize (PTY mode only — ghostty handles resize via sizeDidChange)

    func resize(cols: Int, rows: Int) {
        guard mode == .pty, cols > 0, rows > 0 else { return }
        processHandle?.resize(cols: UInt16(cols), rows: UInt16(rows))
    }

    // MARK: - PTY Event Handling

    private func handle(_ event: TerminalEvent) {
        switch event {
        case .stdout(let text):
            handleStandardOutput(text)
        case .stderr(let text):
            append(.error, text)
            appendToCaptureOutput(text)
        case .exit(let code):
            append(.info, "Shell exited with status \(code)")
            flushPendingOutput()
            finalizeActiveCaptureIfNeeded(exitCode: Int(code))
            processHandle = nil
            status = .stopped
        }
    }

    private func handleStandardOutput(_ text: String) {
        extractOSC7(from: text)

        if tuiPassthroughEnabled {
            append(.output, text)
            return
        }

        for token in parser.feed(text) {
            switch token {
            case .text(let visibleText):
                append(.output, visibleText)
                handleVisibleTerminalText(visibleText)
            case .event(let event):
                handleControlEvent(event)
            }
        }
    }

    private func extractOSC7(from text: String) {
        guard let range = text.range(of: "\u{1B}]7;") else { return }
        let afterPrefix = text[range.upperBound...]
        let terminator = afterPrefix.firstIndex(of: "\u{07}") ?? afterPrefix.range(of: "\u{1B}\\")?.lowerBound
        guard let terminator else { return }
        let uri = String(afterPrefix[..<terminator])
        if let url = URL(string: uri), url.scheme == "file" {
            currentWorkingDirectory = url.path
        }
    }

    private func handleVisibleTerminalText(_ text: String) {
        guard !text.isEmpty, var activeCapture else { return }

        switch activeCapture.stage {
        case .command:
            activeCapture.commandText.append(text)
        case .output:
            activeCapture.outputText.append(text)
        }

        self.activeCapture = activeCapture
    }

    private func appendToCaptureOutput(_ text: String) {
        guard var activeCapture, activeCapture.stage == .output else { return }
        activeCapture.outputText.append(text)
        self.activeCapture = activeCapture
    }

    private func handleControlEvent(_ event: OSC133Event) {
        switch event {
        case .promptStart:
            break
        case .commandInputStart:
            activeCapture = TerminalBlockCapture(startedAt: Date(), finishedAt: Date(), stage: .command)
        case .commandExecuted:
            guard var activeCapture else { return }
            activeCapture.commandText = sanitizeCommand(activeCapture.commandText)
            activeCapture.stage = .output
            self.activeCapture = activeCapture
        case .commandFinished(let exitCode):
            finalizeActiveCaptureIfNeeded(exitCode: exitCode)
        }
    }

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

    // MARK: - Ghostty Action Handlers

    func updateWorkingDirectory(_ url: URL) {
        currentWorkingDirectory = url.path
    }

    func updateTitle(_ title: String) {
        // Title display will be wired in future work
    }

    func handleCommandFinished(exitCode: Int16, durationNs: UInt64) {
        let code = exitCode == -1 ? nil : Int(exitCode)

        // In ghostty mode, read command text from the temp file written by preexec hooks
        if mode == .ghostty {
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
        switch mode {
        case .pty:
            flushPendingOutput()
            processHandle = nil
        case .ghostty:
            surfaceView = nil
            cleanupTemporaryFiles()
        }
        finalizeActiveCaptureIfNeeded(exitCode: Int(exitCode))
        status = .stopped
    }

    func handleSurfaceClosed() {
        stop()
    }

    // MARK: - Helpers

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

    // MARK: - PTY Output Coalescing

    private func append(_ kind: Line.Kind, _ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        pendingTranscriptText.append(normalized)
        let splitLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        for item in splitLines {
            pendingLines.append((kind, String(item)))
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.coalesceInterval))
            self?.flushPendingOutput()
        }
    }

    /// Flushes buffered output to `transcriptLog` and `lines`.
    /// Internal (not private) so tests can drain the coalescing buffer synchronously.
    func flushPendingOutput() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingTranscriptText.isEmpty else { return }

        transcriptLog.append(pendingTranscriptText)
        for (kind, text) in pendingLines {
            lines.append(Line(kind: kind, text: text))
        }

        pendingTranscriptText.removeAll(keepingCapacity: true)
        pendingLines.removeAll(keepingCapacity: true)
    }
}
