import Combine
import Foundation

struct TerminalNotification {
    let title: String
    let body: String
    let receivedAt: Date
}

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
    @Published private(set) var isAlternateScreen = false
    @Published private(set) var isHistorySearchActive = false
    @Published private(set) var isHistoryPopupActive = false
    @Published private(set) var hoverUrl: String?
    @Published private(set) var pendingNotification: TerminalNotification?
    @Published private(set) var isDragTarget = false

    /// Published so prompt-driven presentation updates can react when the input
    /// bar is created or torn down outside the same render pass.
    @Published private(set) var inputBarState: InputBarState?

    private var blockStore: BlockStore?
    private var searchStateCancellable: AnyCancellable?
    private var popupStateCancellable: AnyCancellable?
    private var activeSessionID: UUID?
    private var activeCapture: TerminalBlockCapture?
    private var blockOrderIndex = 0
    private var altScreenTimer: Timer?

    /// Tracks launch parameters for auto-restart on immediate crash.
    private var launchParams: (shellPath: String, workingDirectory: URL, bottomAlign: Bool)?
    private var launchTime: Date?
    private var restartCount = 0
    private static let maxRestarts = 2
    private static let immediateExitThreshold: TimeInterval = 2

    /// Temporary files created for shell integration, cleaned up on stop/deinit.
    private var temporaryURLs: [URL] = []

    /// Unique session identifier passed to shell integration scripts for command capture.
    private(set) var shellSessionID: String = UUID().uuidString

    init() {}

    deinit {
        altScreenTimer?.invalidate()
    }

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

    func start(shellPath: String, workingDirectory: URL, bottomAlign: Bool = false, initialSize: NSSize? = nil) {
        guard surfaceView == nil else { return }

        launchParams = (shellPath, workingDirectory, bottomAlign)
        launchTime = Date()
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
            sessionID: shellSessionID,
            bottomAlign: bottomAlign
        )
        temporaryURLs = config.temporaryURLs

        let view = GhosttySurfaceView(app: app, config: config, initialSize: initialSize)
        view.session = self
        view.registerWithApp()
        surfaceView = view

        // Set the PTY size immediately so tput/LINES reflect the correct
        // dimensions before the shell's first prompt fires.
        if let initialSize {
            view.sizeDidChange(initialSize)
        }

        prepareInputBar()
        startAltScreenPolling()
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
        altScreenTimer?.invalidate()
        altScreenTimer = nil
        surfaceView = nil
        isAtPrompt = false
        isAlternateScreen = false
        teardownInputBar()
        cleanupTemporaryFiles()

        if status != .failed {
            status = .stopped
        }
    }

    // MARK: - Alternate Screen

    func checkAlternateScreen() {
        guard let surface = surfaceView?.surface else { return }

        // These ghostty calls acquire renderer_state.mutex which the renderer
        // thread holds during frame updates. Dispatch to a background queue so
        // the main thread never stalls waiting for the lock.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let mouseCap = ghostty_surface_mouse_captured(surface)
            let confirmQuit = ghostty_surface_needs_confirm_quit(surface)
            let isTUI = mouseCap || confirmQuit
            DispatchQueue.main.async {
                guard let self else { return }
                if isTUI != self.isAlternateScreen {
                    self.isAlternateScreen = isTUI
                }
            }
        }
    }

    private func startAltScreenPolling() {
        altScreenTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkAlternateScreen()
        }
    }

    // MARK: - Input Bar

    func sendFromInputBar(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Send text via ghostty_surface_text (handles bracketed paste encoding),
        // then send a Return key event to execute. We must not include '\n' in
        // the text because ghostty_surface_text is a paste API — newlines inside
        // bracketed paste are treated as literal characters, not execution.
        send(text: trimmed)
        sendReturnKey()
    }

    /// Send a Return key press directly to Ghostty, bypassing paste encoding.
    /// Used by the input bar to execute commands after pasting text.
    private func sendReturnKey() {
        guard let surface = surfaceView?.surface else { return }

        var key_ev = ghostty_input_key_s()
        key_ev.keycode = 0x24 // Return (macOS virtual keycode)
        key_ev.mods = ghostty_input_mods_e(0)
        key_ev.consumed_mods = ghostty_input_mods_e(0)
        key_ev.composing = false
        key_ev.unshifted_codepoint = 0x0D

        key_ev.action = GHOSTTY_ACTION_PRESS
        "\r".withCString { ptr in
            key_ev.text = ptr
            ghostty_surface_key(surface, key_ev)
        }

        key_ev.action = GHOSTTY_ACTION_RELEASE
        key_ev.text = nil
        ghostty_surface_key(surface, key_ev)
    }

    /// Create the InputBarState eagerly (no editor view yet) so the input bar
    /// region is present in the layout from the very first frame.
    func prepareInputBar() {
        guard inputBarState == nil else { return }
        let state = InputBarState()
        state.keyHandler.terminalSession = self
        state.historyController.blockStore = blockStore
        state.suggestionEngine.blockStore = blockStore
        state.completionController.terminalSession = self
        state.completionController.onDismiss = { [weak state] in
            state?.refreshGhostSuffix()
        }
        state.observeSession()
        inputBarState = state

        searchStateCancellable = state.historyController.$isSearchActive
            .sink { [weak self] active in
                if self?.isHistorySearchActive != active {
                    self?.isHistorySearchActive = active
                }
            }

        popupStateCancellable = state.historyController.$isPopupActive
            .sink { [weak self] active in
                if self?.isHistoryPopupActive != active {
                    self?.isHistoryPopupActive = active
                }
            }
    }

    /// Create the editor view inside the existing InputBarState once theme info
    /// is available from the view layer.
    func setupInputBar(theme: TerminalTheme, fontFamily: String, fontSize: Double, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        prepareInputBar()
        inputBarState?.createView(theme: theme, fontFamily: fontFamily, fontSize: fontSize, cursorConfig: cursorConfig, cursorBlink: cursorBlink)
    }

    private func teardownInputBar() {
        inputBarState?.completionController.dismiss()
        inputBarState?.editorView?.focusDidChange(false)
        inputBarState?.editorView?.pauseDisplayLink()
        searchStateCancellable = nil
        popupStateCancellable = nil
        inputBarState = nil
        isHistorySearchActive = false
        isHistoryPopupActive = false
    }

    // MARK: - Action Handlers

    func setDragTarget(_ active: Bool) {
        guard isDragTarget != active else { return }
        isDragTarget = active
    }

    func updateWorkingDirectory(_ url: URL) {
        let path = url.path
        guard path != currentWorkingDirectory else { return }
        currentWorkingDirectory = path
    }

    func updateHoverUrl(_ url: String?) {
        guard hoverUrl != url else { return }
        hoverUrl = url
    }

    func handleDesktopNotification(title: String, body: String) {
        pendingNotification = TerminalNotification(title: title, body: body, receivedAt: Date())
    }

    func clearNotification() {
        guard pendingNotification != nil else { return }
        pendingNotification = nil
    }

    func updateTitle(_ title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextTitle = normalized.isEmpty ? nil : normalized
        guard shellTitle != nextTitle else { return }
        shellTitle = nextTitle
    }

    func handleCommandFinished(exitCode: Int16, durationNs: UInt64) {
        let code = exitCode == -1 ? nil : Int(exitCode)

        let rawCommandText = readAndCleanupCommandFile()
        // Respect HIST_IGNORE_SPACE: commands starting with a space are not recorded
        let commandText = rawCommandText?.hasPrefix(" ") == true ? nil : rawCommandText?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        inputBarState?.suggestionEngine.invalidateCache()
        isAtPrompt = true
    }

    /// Reads and removes the shell-side command temp file for this session.
    func readAndCleanupCommandFile() -> String? {
        let path = NSTemporaryDirectory() + "tesara-cmd-\(shellSessionID).txt"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        try? FileManager.default.removeItem(atPath: path)
        return String(data: data, encoding: .utf8)
    }

    func handleChildExited(exitCode: UInt32) {
        let wasImmediate = launchTime.map { Date().timeIntervalSince($0) < Self.immediateExitThreshold } ?? false

        altScreenTimer?.invalidate()
        altScreenTimer = nil
        surfaceView = nil
        isAtPrompt = false
        isAlternateScreen = false
        teardownInputBar()
        cleanupTemporaryFiles()
        finalizeActiveCaptureIfNeeded(exitCode: Int(exitCode))

        // Auto-restart if the shell died immediately (e.g. race during app init).
        if wasImmediate, restartCount < Self.maxRestarts, let params = launchParams {
            restartCount += 1
            shellSessionID = UUID().uuidString
            // Delay slightly to avoid tight restart loops
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.start(shellPath: params.shellPath, workingDirectory: params.workingDirectory, bottomAlign: params.bottomAlign)
            }
            return
        }

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
        let normalized = command
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .removingAnsiSequences()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanupTemporaryFiles() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
    }

    // MARK: - Bottom Align

    /// Creates a signal file that the shell integration's WINCH handler reads.
    /// When the input bar appears, the terminal surface resizes, triggering
    /// SIGWINCH. The shell sees the file and moves the cursor to the bottom row.
    func requestBottomAlign() {
        guard status == .running else { return }
        let path = NSTemporaryDirectory() + "tesara-ba-\(shellSessionID)"
        FileManager.default.createFile(atPath: path, contents: nil)
        // Clean up after a few seconds in case SIGWINCH didn't fire.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [path] in
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Stale Temp File Cleanup

    /// Removes Tesara temp files older than the given threshold (default 24 hours).
    /// Safe to call on launch — only deletes stale files, not those from running instances.
    static func cleanupStaleTempFiles(olderThan threshold: TimeInterval = 86400) {
        let tmpDir = NSTemporaryDirectory()
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-threshold)
        // Command capture files contain sensitive data — use a shorter threshold
        let cmdCutoff = Date().addingTimeInterval(-3600)
        guard let contents = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        let prefixes = ["tesara-cmd-", "tesara-ba-", "tesara-zsh-", "tesara-bash-", "tesara-fish-", "tesara-paste-"]
        for entry in contents where prefixes.contains(where: { entry.hasPrefix($0) }) {
            let path = (tmpDir as NSString).appendingPathComponent(entry)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            let effectiveCutoff = entry.hasPrefix("tesara-cmd-") ? cmdCutoff : cutoff
            guard modified < effectiveCutoff else { continue }
            try? fm.removeItem(atPath: path)
        }
    }
}

extension String {
    func removingAnsiSequences() -> String {
        var cleaned = ""
        let scalars = Array(self.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{001b}" {
                index += 1
                guard index < scalars.count else { break }
                let next = scalars[index]
                switch next {
                case "[":
                    index += 1
                    while index < scalars.count {
                        let c = scalars[index]
                        index += 1
                        if (0x40...0x7e).contains(c.value) {
                            break
                        }
                    }
                case "]":
                    index += 1
                    while index < scalars.count {
                        let c = scalars[index]
                        if c == "\u{0007}" {
                            index += 1
                            break
                        }
                        if c == "\u{001b}", index + 1 < scalars.count, scalars[index + 1] == "\\" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                case "P", "_", "X":
                    index += 1
                    while index < scalars.count {
                        let c = scalars[index]
                        if c == "\u{001b}", index + 1 < scalars.count, scalars[index + 1] == "\\" {
                            index += 2
                            break
                        }
                        index += 1
                    }
                default:
                    index += 1
                }
                continue
            }
            if scalar == "\u{0007}" {
                index += 1
                continue
            }
            cleaned.append(Character(scalar))
            index += 1
        }
        return cleaned
    }
}
