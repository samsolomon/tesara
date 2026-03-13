import AppKit

/// Singleton managing the ghostty_app_t lifecycle and routing actions to surfaces.
///
/// Not `@MainActor` because C callbacks from libghostty need direct access.
/// All mutable state is only modified on the main thread (via `tick()` or explicit dispatch).
final class GhosttyApp: @unchecked Sendable {
    static let shared = GhosttyApp()

    private static var didGlobalInit = false

    private(set) var app: ghostty_app_t?

    /// Maps surface userdata pointers back to their TerminalSession for action routing.
    private var surfaceRegistry: [UnsafeRawPointer: TerminalSession] = [:]

    /// The currently focused surface, used for clipboard operations.
    /// Set by the surface view in Phase 3 via `setFocusedSurface(_:)`.
    private(set) var focusedSurface: ghostty_surface_t?

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
                print("[GhosttyApp] ghostty_init failed with code \(initResult)")
                return
            }
            Self.didGlobalInit = true
        }

        let config = GhosttyConfig.makeConfig(theme: theme, settings: settings)
        guard config != nil else {
            print("[GhosttyApp] Failed to create config")
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
        if app == nil {
            print("[GhosttyApp] Failed to create ghostty app")
            ghostty_config_free(config)
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func deinitialize() {
        if let app {
            ghostty_app_free(app)
        }
        app = nil
        surfaceRegistry.removeAll()
    }

    // MARK: - Surface Registry

    func register(session: TerminalSession, for surfaceUserdata: UnsafeRawPointer) {
        surfaceRegistry[surfaceUserdata] = session
    }

    func unregister(surfaceUserdata: UnsafeRawPointer) {
        surfaceRegistry.removeValue(forKey: surfaceUserdata)
    }

    func setFocusedSurface(_ surface: ghostty_surface_t?) {
        focusedSurface = surface
    }

    func session(for surfaceUserdata: UnsafeRawPointer) -> TerminalSession? {
        surfaceRegistry[surfaceUserdata]
    }

    // MARK: - Config Updates

    @MainActor
    func updateConfig(theme: TerminalTheme, settings: AppSettings) {
        guard let app else { return }

        let config = GhosttyConfig.makeConfig(theme: theme, settings: settings)
        guard config != nil else { return }

        ghostty_app_update_config(app, config)
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

        case GHOSTTY_ACTION_CLOSE_WINDOW,
             GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_CLOSE_TAB,
             GHOSTTY_ACTION_NEW_SPLIT,
             GHOSTTY_ACTION_QUIT:
            // Window management — will be handled in Phase 3
            return false

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

    // MARK: - Helpers

    private func sessionFromTarget(_ target: ghostty_target_s) -> TerminalSession? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface else { return nil }

        let userdata = ghostty_surface_userdata(surface)
        guard let userdata else { return nil }
        return surfaceRegistry[UnsafeRawPointer(userdata)]
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
    guard let state, let surface = GhosttyApp.shared.focusedSurface else { return false }

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
    guard let userdata else { return }

    DispatchQueue.main.async {
        let session = GhosttyApp.shared.session(for: UnsafeRawPointer(userdata))
        session?.handleSurfaceClosed()
    }
}
