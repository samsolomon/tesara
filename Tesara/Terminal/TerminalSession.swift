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
    @Published private(set) var transcriptLog = TranscriptLog()
    @Published private(set) var launchError: String?
    @Published private(set) var capturedBlockCount = 0
    @Published var tuiPassthroughEnabled = false
    @Published private(set) var currentWorkingDirectory: String?

    private let launcher: TerminalLaunching
    private let parser: OSC133Parsing
    private var processHandle: TerminalProcessHandle?
    private var blockStore: BlockStore?
    private var activeSessionID: UUID?
    private var activeCapture: TerminalBlockCapture?
    private var blockOrderIndex = 0

    // Render coalescing: buffer appends and flush on a timer
    private var pendingTranscriptText = ""
    private var pendingLines: [(Line.Kind, String)] = []
    private var flushTask: Task<Void, Never>?
    private static let coalesceInterval: TimeInterval = 0.008  // 8ms ≈ 120fps cap

    init(launcher: TerminalLaunching = PTYShellLauncher(), parser: OSC133Parsing = OSC133Parser()) {
        self.launcher = launcher
        self.parser = parser
    }

    func configure(blockStore: BlockStore) {
        if self.blockStore == nil {
            self.blockStore = blockStore
        }
    }

    func start(shellPath: String, workingDirectory: URL) {
        guard processHandle == nil else {
            return
        }

        status = .starting
        lines.removeAll()
        transcriptLog.reset()
        launchError = nil
        capturedBlockCount = 0
        blockOrderIndex = 0
        parser.reset()
        activeCapture = nil
        activeSessionID = blockStore?.startSession(shellPath: shellPath, workingDirectory: workingDirectory)
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

        send(text: trimmed + "\n")
    }

    func send(text: String) {
        guard !text.isEmpty else {
            return
        }

        do {
            try processHandle?.send(text)
        } catch {
            append(.error, error.localizedDescription)
        }
    }

    func stop() {
        flushPendingOutput()
        processHandle?.stop()
        processHandle = nil
        if status != .failed {
            status = .stopped
        }
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            return
        }

        processHandle?.resize(cols: UInt16(cols), rows: UInt16(rows))
    }

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
        // OSC 7 format: ESC ] 7 ; file://hostname/path BEL (or ST)
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
        guard !text.isEmpty, var activeCapture else {
            return
        }

        switch activeCapture.stage {
        case .command:
            activeCapture.commandText.append(text)
        case .output:
            activeCapture.outputText.append(text)
        }

        self.activeCapture = activeCapture
    }

    private func appendToCaptureOutput(_ text: String) {
        guard var activeCapture, activeCapture.stage == .output else {
            return
        }

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
            guard var activeCapture else {
                return
            }
            activeCapture.commandText = sanitizeCommand(activeCapture.commandText)
            activeCapture.stage = .output
            self.activeCapture = activeCapture
        case .commandFinished(let exitCode):
            finalizeActiveCaptureIfNeeded(exitCode: exitCode)
        }
    }

    private func finalizeActiveCaptureIfNeeded(exitCode: Int?) {
        guard var activeCapture, let activeSessionID else {
            return
        }

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

    private func append(_ kind: Line.Kind, _ text: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        // Buffer the text instead of publishing immediately
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
