import AppKit
import Carbon

/// NSView subclass hosting a `ghostty_surface_t` for Metal-rendered terminal output.
///
/// Direct counterpart to Ghostty's `SurfaceView_AppKit.swift`. The session owns this view —
/// SwiftUI never creates or destroys it (see `GhosttySurfaceRepresentable`).
class GhosttySurfaceView: NSView, NSTextInputClient {

    // MARK: - Public State

    private(set) var surface: ghostty_surface_t?
    weak var session: TerminalSession?

    // MARK: - Private State

    // IME / keyboard
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var lastPerformKeyEvent: TimeInterval?
    private var focused: Bool = false

    // Mouse
    private var prevPressureStage: Int = 0
    private var suppressNextLeftMouseUp: Bool = false

    // Event monitor
    private var eventMonitor: Any?

    // Stored content size for backing property changes
    private var contentSize: CGSize = .zero

    // Cached userdata pointer — stored at init time so deinit doesn't use Unmanaged on a deallocating object
    private var surfaceUserdata: UnsafeRawPointer?

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Init

    init(app: ghostty_app_t, config: GhosttySurfaceConfig) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true

        // Register for screen-change notifications before surface creation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )

        // Local event monitor for keyUp (Cmd+key) and leftMouseDown (focus transfer)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyUp, .leftMouseDown]
        ) { [weak self] event in
            self?.localEventHandler(event)
        }

        // Build surface config and create surface
        let surface = config.withCValue(view: self) { cfg in
            ghostty_surface_new(app, &cfg)
        }
        guard let surface else {
            print("[GhosttySurfaceView] Failed to create ghostty surface")
            return
        }
        self.surface = surface

        // Registration with GhosttyApp is deferred to registerWithApp()
        // because the session is set after init.

        // Setup tracking area for mouse events
        updateTrackingAreas()
    }

    /// Deferred registration — call after session is set.
    /// Must be called exactly once after assigning `session`.
    func registerWithApp() {
        precondition(session != nil, "GhosttySurfaceView.registerWithApp() called before session was set")
        let userdata = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        surfaceUserdata = userdata
        GhosttyApp.shared.register(session: session!, for: userdata)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }

        trackingAreas.forEach { removeTrackingArea($0) }

        if let surface {
            if let surfaceUserdata {
                GhosttyApp.shared.unregister(surfaceUserdata: surfaceUserdata)
            }
            ghostty_surface_free(surface)
        }
    }

    // MARK: - Resize

    func sizeDidChange(_ size: CGSize) {
        contentSize = size
        let scaledSize = self.convertToBacking(size)
        setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
    }

    private func setSurfaceSize(width: UInt32, height: UInt32) {
        guard let surface else { return }
        ghostty_surface_set_size(surface, width, height)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        // Update layer contentsScale to match window backing, preventing compositor scaling
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        guard let surface else { return }

        // Detect per-axis scale factor — guard against zero frame (before layout)
        guard self.frame.size.width > 0, self.frame.size.height > 0 else { return }
        let fbFrame = self.convertToBacking(self.frame)
        let xScale = fbFrame.size.width / self.frame.size.width
        let yScale = fbFrame.size.height / self.frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        // Scale factor change also changes framebuffer size
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let scaledSize = self.convertToBacking(contentSize)
        setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))
    }

    @objc private func windowDidChangeScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === self.window else { return }
        viewDidChangeBackingProperties()
    }

    // MARK: - Focus

    func focusDidChange(_ isFocused: Bool) {
        guard let surface, self.focused != isFocused else { return }
        self.focused = isFocused

        if !isFocused {
            suppressNextLeftMouseUp = false
        }

        ghostty_surface_set_focus(surface, isFocused)
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: frame,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .inVisibleRect,
                .activeAlways,
            ],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Local Event Monitor

    private func localEventHandler(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyUp:
            return localEventKeyUp(event)
        case .leftMouseDown:
            return localEventLeftMouseDown(event)
        default:
            return event
        }
    }

    private func localEventKeyUp(_ event: NSEvent) -> NSEvent? {
        // Command+key events don't trigger keyUp via responder chain
        guard event.modifierFlags.contains(.command), focused else { return event }
        self.keyUp(with: event)
        return nil
    }

    private func localEventLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window != nil,
              window == event.window else { return event }

        let location = convert(event.locationInWindow, from: nil)
        guard hitTest(location) == self else { return event }

        suppressNextLeftMouseUp = false

        // Already first responder — normal click
        guard window.firstResponder !== self else { return event }

        // Window already focused — this click is only for focus transfer
        if NSApp.isActive && window.isKeyWindow {
            window.makeFirstResponder(self)
            suppressNextLeftMouseUp = true
            return nil
        }

        window.makeFirstResponder(self)
        return event
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            self.interpretKeyEvents([event])
            return
        }

        // Translate mods for option-as-alt etc.
        let translationModsGhostty = GhosttyInput.eventModifierFlags(
            mods: ghostty_surface_key_translation_mods(
                surface,
                GhosttyInput.ghosttyMods(event.modifierFlags)
            )
        )

        // Preserve hidden dead-key bits by only toggling known modifier flags
        var translationMods = event.modifierFlags
        for flag: NSEvent.ModifierFlags in [.shift, .control, .option, .command] {
            if translationModsGhostty.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }

        // IMPORTANT: reuse original event when mods match for Korean IME compatibility
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedTextBefore = markedText.length > 0

        let keyboardIdBefore: String? = if !markedTextBefore {
            KeyboardLayout.id
        } else {
            nil
        }

        self.lastPerformKeyEvent = nil
        self.interpretKeyEvents([translationEvent])

        // Input method switched — don't send to terminal
        if !markedTextBefore && keyboardIdBefore != KeyboardLayout.id {
            return
        }

        syncPreedit(clearIfNeeded: markedTextBefore)

        if let list = keyTextAccumulator, list.count > 0 {
            for text in list {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            _ = keyAction(
                action,
                event: event,
                translationEvent: translationEvent,
                text: translationEvent.ghosttyCharacters,
                composing: markedText.length > 0 || markedTextBefore
            )
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        if hasMarkedText() { return }

        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)

        var action = GHOSTTY_ACTION_RELEASE
        if mods.rawValue & mod != 0 {
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36:
                sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default:
                sidePressed = true
            }

            if sidePressed {
                action = GHOSTTY_ACTION_PRESS
            }
        }

        _ = keyAction(action, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard focused else { return false }

        // Check if this is a ghostty binding
        var ghosttyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding: Bool = (event.characters ?? "").withCString { ptr in
            ghosttyEvent.text = ptr
            var flags: ghostty_binding_flags_e = ghostty_binding_flags_e(0)
            return ghostty_surface_key_is_binding(surface, ghosttyEvent, &flags)
        }

        if isBinding {
            self.keyDown(with: event)
            return true
        }

        let equivalent: String
        switch event.charactersIgnoringModifiers {
        case "\r":
            guard event.modifierFlags.contains(.control) else { return false }
            equivalent = "\r"

        case "/":
            guard event.modifierFlags.contains(.control),
                  event.modifierFlags.isDisjoint(with: [.shift, .command, .option]) else { return false }
            equivalent = "_"

        default:
            if event.timestamp == 0 { return false }

            guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) else {
                lastPerformKeyEvent = nil
                return false
            }

            if let lastPerformKeyEvent {
                self.lastPerformKeyEvent = nil
                if lastPerformKeyEvent == event.timestamp {
                    equivalent = event.characters ?? ""
                    break
                }
            }

            lastPerformKeyEvent = event.timestamp
            return false
        }

        guard let finalEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: equivalent,
            charactersIgnoringModifiers: equivalent,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        ) else { return false }

        self.keyDown(with: finalEvent)
        return true
    }

    // MARK: - Key Action Helper

    @discardableResult
    private func keyAction(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        translationEvent: NSEvent? = nil,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var key_ev = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        key_ev.composing = composing

        if let text, text.count > 0,
           let codepoint = text.utf8.first, codepoint >= 0x20 {
            return text.withCString { ptr in
                key_ev.text = ptr
                return ghostty_surface_key(surface, key_ev)
            }
        } else {
            return ghostty_surface_key(surface, key_ev)
        }
    }

    // MARK: - NSTextInputClient

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange() }
        return NSRange(0...(markedText.length - 1))
    }

    func selectedRange() -> NSRange {
        NSRange()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString:
            self.markedText = NSMutableAttributedString(attributedString: v)
        case let v as String:
            self.markedText = NSMutableAttributedString(string: v)
        default:
            break
        }

        // If not inside keyDown, sync preedit immediately
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else {
            return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        // Ghostty coordinates are top-left origin, convert to bottom-left for AppKit
        let viewRect = NSRect(
            x: x,
            y: frame.size.height - y,
            width: width,
            height: height
        )

        let winRect = self.convert(viewRect, to: nil)
        guard let window else { return winRect }
        return window.convertToScreen(winRect)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }

        var chars = ""
        switch string {
        case let v as NSAttributedString:
            chars = v.string
        case let v as String:
            chars = v
        default:
            return
        }

        unmarkText()

        // If inside keyDown, accumulate for batch processing
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }

        // Outside keyDown — send directly
        guard let surface else { return }
        chars.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
        }
    }

    override func doCommand(by selector: Selector) {
        // Re-dispatch command+key events that performKeyEquivalent deferred
        if let lastPerformKeyEvent,
           let current = NSApp.currentEvent,
           lastPerformKeyEvent == current.timestamp {
            NSApp.sendEvent(current)
            return
        }

        // Native scroll commands
        switch selector {
        case #selector(moveToBeginningOfDocument(_:)):
            performBindingAction("scroll_to_top")
        case #selector(moveToEndOfDocument(_:)):
            performBindingAction("scroll_to_bottom")
        default:
            break
        }
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }

        if markedText.length > 0 {
            let str = markedText.string
            let len = str.utf8CString.count
            if len > 0 {
                str.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(len - 1))
                }
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: - Edit Menu Actions

    @IBAction func copy(_ sender: Any?) {
        performBindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        performBindingAction("paste_from_clipboard")
    }

    private func performBindingAction(_ action: String) {
        guard let surface else { return }
        ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextLeftMouseUp {
            suppressNextLeftMouseUp = false
            return
        }

        prevPressureStage = 0

        guard let surface else { return }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
        ghostty_surface_mouse_pressure(surface, 0, 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods) {
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return super.rightMouseUp(with: event) }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        if ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods) {
            return
        }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        let button = GhosttyInput.mouseButton(from: event.buttonNumber)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, button, mods)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        let button = GhosttyInput.mouseButton(from: event.buttonNumber)
        ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, button, mods)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = self.convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let surface else { return }
        let pos = self.convert(event.locationInWindow, from: nil)
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        if NSEvent.pressedMouseButtons != 0 { return }
        let mods = GhosttyInput.ghosttyMods(event.modifierFlags)
        ghostty_surface_mouse_pos(surface, -1, -1, mods)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas

        if precision {
            x *= 2
            y *= 2
        }

        let scrollMods = GhosttyInput.ScrollMods(
            precision: precision,
            momentum: .init(event.momentumPhase)
        )
        ghostty_surface_mouse_scroll(surface, x, y, scrollMods.cScrollMods)
    }

    override func pressureChange(with event: NSEvent) {
        guard let surface else { return }

        ghostty_surface_mouse_pressure(surface, UInt32(event.stage), Double(event.pressure))

        guard prevPressureStage < 2 else { return }
        prevPressureStage = event.stage
        guard event.stage == 2 else { return }

        guard UserDefaults.standard.bool(forKey: "com.apple.trackpad.forceClick") else { return }
        quickLook(with: event)
    }
}
