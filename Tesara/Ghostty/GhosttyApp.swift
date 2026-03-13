import AppKit
import os

/// Singleton managing the ghostty_app_t lifecycle and routing actions to surfaces.
///
/// Not `@MainActor` because C callbacks from libghostty need direct access.
/// `surfaceRegistry` is protected by `lock` because `unregister` can be called from
/// `GhosttySurfaceView.deinit` which may run off the main thread.
final class GhosttyApp: @unchecked Sendable {
    static let shared = GhosttyApp()

    struct TerminalBehavior {
        var pasteProtectionMode: PasteProtectionMode = .multiline
    }

    private static var didGlobalInit = false

    private(set) var app: ghostty_app_t?

    /// Protects surfaceRegistry from concurrent access (deinit can run off main thread).
    private let lock = os.OSAllocatedUnfairLock()

    /// Maps surface userdata pointers back to their TerminalSession for action routing.
    private var surfaceRegistry: [UnsafeRawPointer: TerminalSession] = [:]

    /// The currently focused surface. Only accessed from the main thread.
    private var focusedSurface: ghostty_surface_t?

    /// Lightweight terminal interaction settings read by AppKit event handlers.
    /// Mutated on the main thread through initialize/updateConfig.
    private(set) var terminalBehavior = TerminalBehavior()

    /// Delegate for routing window management actions to the workspace.
    /// Set in TesaraApp.onAppear after initialize().
    @MainActor weak var actionDelegate: GhosttyActionDelegate?

    /// Tracks whether we've already logged the "new window not supported" message.
    /// Only accessed from @MainActor context (handleAction is @MainActor).
    private var didLogNewWindowUnsupported = false

    private init() {}

    // MARK: - Lifecycle

    @MainActor
    func initialize(theme: TerminalTheme, settings: AppSettings) {
        guard app == nil else { return }

        // Skip initialization during unit tests
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // Global ghostty init (must be called exactly once)
        if !Self.didGlobalInit {
            let initResult = ghostty_init(0, nil)
            guard initResult == GHOSTTY_SUCCESS else {
                LocalLogStore.shared.log("[GhosttyApp] ghostty_init failed with code \(initResult)")
                return
            }
            Self.didGlobalInit = true
        }

        terminalBehavior.pasteProtectionMode = settings.pasteProtectionMode

        let config = GhosttyConfig.makeConfig(theme: theme, settings: settings)
        guard config != nil else {
            LocalLogStore.shared.log("[GhosttyApp] Failed to create config")
            return
        }

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false
        runtime.wakeup_cb = ghosttyWakeupCallback
        runtime.action_cb = ghosttyActionCallback
        runtime.read_clipboard_cb = ghosttyReadClipboardCallback
        runtime.confirm_read_clipboard_cb = nil
        runtime.write_clipboard_cb = ghosttyWriteClipboardCallback
        runtime.close_surface_cb = ghosttyCloseSurfaceCallback

        app = ghostty_app_new(&runtime, config)
        // ghostty_app_new copies config data — always free the config after use
        ghostty_config_free(config)
        if app == nil {
            LocalLogStore.shared.log("[GhosttyApp] Failed to create ghostty app")
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    @MainActor
    func deinitialize() {
        if let app {
            ghostty_app_free(app)
        }
        app = nil
        focusedSurface = nil
        lock.withLock {
            surfaceRegistry.removeAll()
        }
    }

    // MARK: - Surface Registry

    func register(session: TerminalSession, for surfaceUserdata: UnsafeRawPointer) {
        lock.withLock {
            surfaceRegistry[surfaceUserdata] = session
        }
    }

    func unregister(surfaceUserdata: UnsafeRawPointer) {
        lock.withLock {
            surfaceRegistry.removeValue(forKey: surfaceUserdata)
        }
    }

    @MainActor
    func setFocusedSurface(_ surface: ghostty_surface_t?) {
        focusedSurface = surface
    }

    func session(for surfaceUserdata: UnsafeRawPointer) -> TerminalSession? {
        lock.withLock {
            surfaceRegistry[surfaceUserdata]
        }
    }

    // MARK: - Config Updates

    @MainActor
    func updateConfig(theme: TerminalTheme, settings: AppSettings) {
        guard let app else { return }

        terminalBehavior.pasteProtectionMode = settings.pasteProtectionMode

        let config = GhosttyConfig.makeConfig(theme: theme, settings: settings)
        guard config != nil else { return }

        ghostty_app_update_config(app, config)
        // ghostty_app_update_config copies config data — always free after use
        ghostty_config_free(config)
    }

    // MARK: - Action Routing

    /// Called during tick() which always runs on the main thread.
    @MainActor
    func handleAction(
        app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_PWD:
            return handlePwd(target: target, action: action)

        case GHOSTTY_ACTION_SET_TITLE:
            return handleSetTitle(target: target, action: action)

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            return handleCommandFinished(target: target, action: action)

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            return handleChildExited(target: target, action: action)

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            return handleMouseShape(action: action)

        case GHOSTTY_ACTION_RENDER:
            // Render is handled by Metal/CAMetalLayer automatically
            return true

        // Note: Standard shortcuts (Cmd+T, Cmd+W, Cmd+D) are handled by AppKit menu
        // key equivalents in TesaraAppCommands before they reach GhosttySurfaceView.
        // These handlers fire only for custom Ghostty keybindings that aren't also
        // menu shortcuts.

        case GHOSTTY_ACTION_NEW_TAB:
            return handleNewTab(target: target)

        case GHOSTTY_ACTION_NEW_SPLIT:
            return handleNewSplit(target: target, direction: action.action.new_split)

        case GHOSTTY_ACTION_CLOSE_TAB:
            return handleCloseTab(target: target, mode: action.action.close_tab_mode)

        case GHOSTTY_ACTION_CLOSE_WINDOW:
            return handleCloseWindow()

        case GHOSTTY_ACTION_NEW_WINDOW:
            if !didLogNewWindowUnsupported {
                LocalLogStore.shared.log("[GhosttyApp] NEW_WINDOW action not supported (single-window app)")
                didLogNewWindowUnsupported = true
            }
            return false

        case GHOSTTY_ACTION_QUIT:
            return handleQuit()

        default:
            return false
        }
    }

    // MARK: - Action Handlers

    @MainActor
    private func handlePwd(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard let session = sessionFromTarget(target) else { return false }
        if let cString = action.action.pwd.pwd {
            let path = String(cString: cString)
            session.updateWorkingDirectory(URL(fileURLWithPath: path))
        }
        return true
    }

    @MainActor
    private func handleSetTitle(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard let session = sessionFromTarget(target) else { return false }
        if let cString = action.action.set_title.title {
            session.updateTitle(String(cString: cString))
        }
        return true
    }

    @MainActor
    private func handleCommandFinished(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard let session = sessionFromTarget(target) else { return false }
        let finished = action.action.command_finished
        session.handleCommandFinished(exitCode: finished.exit_code, durationNs: finished.duration)
        return true
    }

    @MainActor
    private func handleChildExited(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard let session = sessionFromTarget(target) else { return false }
        let childExited = action.action.child_exited
        session.handleChildExited(exitCode: childExited.exit_code)
        return true
    }

    private func handleMouseShape(action: ghostty_action_s) -> Bool {
        let cursor: NSCursor = switch action.action.mouse_shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            .iBeam
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            .crosshair
        case GHOSTTY_MOUSE_SHAPE_GRAB:
            .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING:
            .closedHand
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP:
            .operationNotAllowed
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            .resizeUpDown
        default:
            .arrow
        }
        cursor.set()
        return true
    }

    // MARK: - Window Management Action Handlers

    @MainActor
    private func handleNewTab(target: ghostty_target_s) -> Bool {
        guard let delegate = actionDelegate else {
            LocalLogStore.shared.log("[GhosttyApp] Action delegate not set, dropping NEW_TAB")
            return false
        }
        let session = sessionFromTarget(target)
        delegate.ghosttyNewTab(inheritingFrom: session)
        return true
    }

    @MainActor
    private func handleNewSplit(target: ghostty_target_s, direction: ghostty_action_split_direction_e) -> Bool {
        guard let delegate = actionDelegate else {
            LocalLogStore.shared.log("[GhosttyApp] Action delegate not set, dropping NEW_SPLIT")
            return false
        }
        guard let session = sessionFromTarget(target) else { return false }

        let splitDirection: PaneNode.SplitDirection
        let panePosition: PaneNode.PanePosition

        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT:
            splitDirection = .horizontal
            panePosition = .second
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            splitDirection = .horizontal
            panePosition = .first
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            splitDirection = .vertical
            panePosition = .second
        case GHOSTTY_SPLIT_DIRECTION_UP:
            splitDirection = .vertical
            panePosition = .first
        default:
            splitDirection = .horizontal
            panePosition = .second
        }

        delegate.ghosttySplit(for: session, direction: splitDirection, newPanePosition: panePosition)
        return true
    }

    @MainActor
    private func handleCloseTab(target: ghostty_target_s, mode: ghostty_action_close_tab_mode_e) -> Bool {
        guard let delegate = actionDelegate else {
            LocalLogStore.shared.log("[GhosttyApp] Action delegate not set, dropping CLOSE_TAB")
            return false
        }
        guard let session = sessionFromTarget(target) else { return false }

        switch mode {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS:
            delegate.ghosttyCloseTab(for: session)
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            delegate.ghosttyCloseOtherTabs(for: session)
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            delegate.ghosttyCloseTabsToRight(of: session)
        default:
            delegate.ghosttyCloseTab(for: session)
        }
        return true
    }

    @MainActor
    private func handleCloseWindow() -> Bool {
        guard let delegate = actionDelegate else {
            LocalLogStore.shared.log("[GhosttyApp] Action delegate not set, dropping CLOSE_WINDOW")
            return false
        }
        delegate.ghosttyCloseWindow()
        return true
    }

    @MainActor
    private func handleQuit() -> Bool {
        guard let delegate = actionDelegate else {
            LocalLogStore.shared.log("[GhosttyApp] Action delegate not set, dropping QUIT")
            return false
        }
        delegate.ghosttyRequestQuit()
        return true
    }

    // MARK: - Helpers

    private func sessionFromTarget(_ target: ghostty_target_s) -> TerminalSession? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface else { return nil }

        let userdata = ghostty_surface_userdata(surface)
        guard let userdata else { return nil }
        return lock.withLock { surfaceRegistry[UnsafeRawPointer(userdata)] }
    }
}

// MARK: - C Callbacks (free functions required by ghostty_runtime_config_s)

private func ghosttyWakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        GhosttyApp.shared.tick()
    }
}

private func ghosttyActionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    guard let app else { return false }

    // Actions are called during tick() which runs on the main thread.
    return MainActor.assumeIsolated {
        GhosttyApp.shared.handleAction(app: app, target: target, action: action)
    }
}

private func ghosttyReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ clipboard: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    // userdata is the surface's userdata (GhosttySurfaceView pointer).
    // This callback fires during tick() which runs on the main thread.
    dispatchPrecondition(condition: .onQueue(.main))
    guard let userdata, let state else { return false }

    let view = Unmanaged<GhosttySurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = view.surface else { return false }

    let pasteboard = NSPasteboard.general
    guard let content = pasteboard.string(forType: .string) else {
        ghostty_surface_complete_clipboard_request(surface, nil, state, false)
        return true
    }

    content.withCString { cString in
        ghostty_surface_complete_clipboard_request(surface, cString, state, true)
    }
    return true
}

private func ghosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ clipboard: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ count: Int,
    _ confirm: Bool
) {
    // This callback fires during tick() which runs on the main thread.
    dispatchPrecondition(condition: .onQueue(.main))
    guard let content, count > 0 else { return }

    let entry = content.pointee
    guard let data = entry.data else { return }
    let string = String(cString: data)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
}

private func ghosttyCloseSurfaceCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    // userdata is the surface's userdata (GhosttySurfaceView pointer).
    // This may fire from a child process thread, so dispatch to main.
    guard let userdata else { return }

    DispatchQueue.main.async {
        let session = GhosttyApp.shared.session(for: UnsafeRawPointer(userdata))
        session?.handleSurfaceClosed()
    }
}
