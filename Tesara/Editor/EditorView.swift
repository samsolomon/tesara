import AppKit
import Metal
import QuartzCore

/// NSView hosting a Metal-rendered rich text editor.
/// Counterpart to GhosttySurfaceView for the editor pane type.
class EditorView: NSView, NSTextInputClient {

    // MARK: - Public State

    weak var session: EditorSession?
    private(set) var focused: Bool = false

    // MARK: - Rendering

    private var metalLayer: CAMetalLayer!
    private var renderer: EditorRenderer?
    private let glyphAtlas = GlyphAtlas()
    private let glyphCache: GlyphCache
    private var layoutEngine: EditorLayoutEngine

    private var renderTimer: Timer?
    private var needsRender: Bool = true

    // MARK: - Scroll

    private var scrollOffsetLine: Int = 0
    private var scrollOffsetPixel: CGFloat = 0
    private var scrollMomentum: CGFloat = 0

    // MARK: - Cursor Blink

    private var cursorVisible: Bool = true
    private var cursorBlinkTimer: Timer?

    // MARK: - Theme Colors

    private var themeColors = EditorLayoutEngine.ThemeColors(
        foreground: SIMD4<UInt8>(204, 204, 204, 255),
        background: SIMD4<UInt8>(30, 30, 30, 255),
        cursor: SIMD4<UInt8>(204, 204, 204, 255),
        selection: SIMD4<UInt8>(60, 90, 150, 128)
    )
    private var backgroundColor: SIMD4<Float> = SIMD4<Float>(30.0/255, 30.0/255, 30.0/255, 1.0)

    // MARK: - Event Monitor

    private var eventMonitor: Any?

    // MARK: - IME

    private var markedText = NSMutableAttributedString()
    private var _markedRange = NSRange(location: NSNotFound, length: 0)

    // MARK: - Content Size

    private var contentSize: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Init

    init(session: EditorSession, theme: TerminalTheme, fontFamily: String, fontSize: CGFloat) {
        self.glyphCache = GlyphCache(atlas: glyphAtlas)
        self.layoutEngine = EditorLayoutEngine(fontFamily: fontFamily, fontSize: fontSize)

        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        self.session = session
        self.wantsLayer = true

        applyTheme(theme)

        // Setup Metal layer
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.layer = metalLayer

        renderer = EditorRenderer(device: device)

        // Wire up render callback
        session.needsRenderCallback = { [weak self] in
            self?.setNeedsRender()
        }

        // Event monitor for focus transfer (same pattern as GhosttySurfaceView)
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown]
        ) { [weak self] event in
            self?.localEventLeftMouseDown(event)
        }

        setupDisplayLink()
        startCursorBlink()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        renderTimer?.invalidate()
        cursorBlinkTimer?.invalidate()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Render Timer

    private func setupDisplayLink() {
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.renderTimerFired()
        }
    }

    private func renderTimerFired() {
        guard needsRender else { return }
        needsRender = false
        renderFrame()
    }

    func setNeedsRender() {
        needsRender = true
        resetCursorBlink()
    }

    func pauseDisplayLink() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    func resumeDisplayLink() {
        if renderTimer == nil {
            setupDisplayLink()
        }
        needsRender = true
    }

    // MARK: - Cursor Blink

    private func startCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.cursorVisible.toggle()
            self.needsRender = true
        }
    }

    private func resetCursorBlink() {
        cursorVisible = true
        startCursorBlink()
    }

    // MARK: - Render

    private func renderFrame() {
        guard let session, let renderer, let metalLayer else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }

        let scale = metalLayer.contentsScale
        let viewport = contentSize.width > 0 ? contentSize : bounds.size

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            firstVisibleLine: scrollOffsetLine,
            viewportHeight: viewport.height,
            scale: scale
        )

        let glyphs = layoutEngine.buildGlyphInstances(
            from: layoutLines,
            cache: glyphCache,
            scale: scale,
            colors: themeColors
        )

        // Build marked text info for IME underline
        let markedTextInfo: EditorLayoutEngine.MarkedTextInfo?
        if markedText.length > 0 {
            markedTextInfo = EditorLayoutEngine.MarkedTextInfo(
                line: session.cursorPosition.line,
                startColumn: session.cursorPosition.column,
                length: markedText.length
            )
        } else {
            markedTextInfo = nil
        }

        let rects = layoutEngine.buildRectInstances(
            selection: session.selection,
            cursorPos: session.cursorPosition,
            cursorVisible: cursorVisible && focused,
            markedText: markedTextInfo,
            layoutLines: layoutLines,
            viewportWidth: viewport.width,
            scale: scale,
            colors: themeColors
        )

        let scrollPixels = CGPoint(x: 0, y: scrollOffsetPixel)

        renderer.render(
            to: drawable,
            viewport: viewport,
            scale: scale,
            scrollOffset: scrollPixels,
            rects: rects,
            glyphs: glyphs,
            backgroundColor: backgroundColor,
            atlas: glyphAtlas
        )
    }

    // MARK: - Size

    func sizeDidChange(_ size: CGSize) {
        contentSize = size
        guard let metalLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scaledSize = CGSize(
            width: size.width * metalLayer.contentsScale,
            height: size.height * metalLayer.contentsScale
        )
        metalLayer.drawableSize = scaledSize
        CATransaction.commit()

        needsRender = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let window, let metalLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        if contentSize.width > 0 {
            sizeDidChange(contentSize)
        }
    }

    // MARK: - Focus

    func focusDidChange(_ isFocused: Bool) {
        guard self.focused != isFocused else { return }
        self.focused = isFocused
        if isFocused {
            resetCursorBlink()
        } else {
            cursorVisible = false
        }
        needsRender = true
    }

    // MARK: - Local Event Monitor (focus transfer)

    private func localEventLeftMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window != nil,
              window == event.window else { return event }

        let location = convert(event.locationInWindow, from: nil)
        guard hitTest(location) == self else { return event }

        guard window.firstResponder !== self else { return event }

        if NSApp.isActive && window.isKeyWindow {
            window.makeFirstResponder(self)
            return nil
        }

        window.makeFirstResponder(self)
        return event
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let session else {
            interpretKeyEvents([event])
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Command key shortcuts
        if mods.contains(.command) {
            if handleCommandShortcut(event, session: session) { return }
        }

        // Arrow keys and special keys
        if let specialKey = event.specialKey {
            handleSpecialKey(specialKey, mods: mods, session: session)
            return
        }

        // Regular character input
        if let chars = event.characters, !chars.isEmpty, !mods.contains(.command), !mods.contains(.control) {
            session.insertText(chars)
            return
        }

        interpretKeyEvents([event])
    }

    private func handleCommandShortcut(_ event: NSEvent, session: EditorSession) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers else { return false }

        switch chars {
        case "a":
            session.selectAll()
            return true
        case "z":
            if mods.contains(.shift) {
                session.redo()
            } else {
                session.undo()
            }
            return true
        case "c":
            session.copy()
            return true
        case "v":
            session.paste()
            return true
        case "x":
            session.cut()
            return true
        default:
            return false
        }
    }

    private func handleSpecialKey(_ key: NSEvent.SpecialKey, mods: NSEvent.ModifierFlags, session: EditorSession) {
        let extending = mods.contains(.shift)

        switch key {
        case .leftArrow:
            if mods.contains(.command) {
                session.moveCursor(.lineStart, extending: extending)
            } else if mods.contains(.option) {
                session.moveCursor(.wordLeft, extending: extending)
            } else {
                session.moveCursor(.left, extending: extending)
            }

        case .rightArrow:
            if mods.contains(.command) {
                session.moveCursor(.lineEnd, extending: extending)
            } else if mods.contains(.option) {
                session.moveCursor(.wordRight, extending: extending)
            } else {
                session.moveCursor(.right, extending: extending)
            }

        case .upArrow:
            if mods.contains(.command) {
                session.moveCursor(.documentStart, extending: extending)
            } else {
                session.moveCursor(.up, extending: extending)
            }

        case .downArrow:
            if mods.contains(.command) {
                session.moveCursor(.documentEnd, extending: extending)
            } else {
                session.moveCursor(.down, extending: extending)
            }

        case .delete: // Backspace
            session.deleteBackward()

        case .deleteForward:
            session.deleteForward()

        case .carriageReturn, .newline, .enter:
            session.insertNewline()

        case .tab:
            session.insertTab()

        case .home:
            session.moveCursor(.documentStart, extending: extending)

        case .end:
            session.moveCursor(.documentEnd, extending: extending)

        case .pageUp:
            scrollPageUp()

        case .pageDown:
            scrollPageDown()

        default:
            break
        }

        needsRender = true
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let location = convert(event.locationInWindow, from: nil)
        let scale = metalLayer?.contentsScale ?? 1.0

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            firstVisibleLine: scrollOffsetLine,
            viewportHeight: contentSize.height > 0 ? contentSize.height : bounds.height,
            scale: scale
        )

        let pos = layoutEngine.hitTest(point: CGPoint(x: location.x * scale, y: (contentSize.height - location.y) * scale), in: layoutLines, scale: scale)
        session.cursorPosition = pos

        if event.clickCount == 2 {
            selectWord(at: pos, session: session)
        } else if event.clickCount == 3 {
            selectLine(at: pos, session: session)
        } else {
            session.selection = nil
        }

        needsRender = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session else { return }
        let location = convert(event.locationInWindow, from: nil)
        let scale = metalLayer?.contentsScale ?? 1.0

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            firstVisibleLine: scrollOffsetLine,
            viewportHeight: contentSize.height > 0 ? contentSize.height : bounds.height,
            scale: scale
        )

        let pos = layoutEngine.hitTest(point: CGPoint(x: location.x * scale, y: (contentSize.height - location.y) * scale), in: layoutLines, scale: scale)
        let anchor = session.selection?.start ?? session.cursorPosition
        session.selection = TextStorage.Range(start: anchor, end: pos)
        session.cursorPosition = pos
        needsRender = true
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        let deltaLines = -event.scrollingDeltaY / layoutEngine.lineHeight
        scrollOffsetPixel += event.scrollingDeltaY

        if abs(deltaLines) >= 1 {
            let lineDelta = Int(deltaLines)
            scrollOffsetLine = max(0, scrollOffsetLine + lineDelta)
            scrollOffsetPixel = 0
        }

        needsRender = true
    }

    private func scrollPageUp() {
        let visibleLines = Int(max(1, (contentSize.height > 0 ? contentSize.height : bounds.height) / layoutEngine.lineHeight))
        scrollOffsetLine = max(0, scrollOffsetLine - visibleLines)
        needsRender = true
    }

    private func scrollPageDown() {
        guard let session else { return }
        let visibleLines = Int(max(1, (contentSize.height > 0 ? contentSize.height : bounds.height) / layoutEngine.lineHeight))
        scrollOffsetLine = min(session.storage.lineCount - 1, scrollOffsetLine + visibleLines)
        needsRender = true
    }

    // MARK: - Selection Helpers

    private func selectWord(at pos: TextStorage.Position, session: EditorSession) {
        let start = session.storage.wordBoundary(from: pos, direction: .left)
        let end = session.storage.wordBoundary(from: pos, direction: .right)
        session.selection = TextStorage.Range(start: start, end: end)
        session.cursorPosition = end
    }

    private func selectLine(at pos: TextStorage.Position, session: EditorSession) {
        let lineStart = TextStorage.Position(line: pos.line, column: 0)
        let lineEnd: TextStorage.Position
        if pos.line < session.storage.lineCount - 1 {
            lineEnd = TextStorage.Position(line: pos.line + 1, column: 0)
        } else {
            lineEnd = TextStorage.Position(line: pos.line, column: session.storage.lineLength(pos.line))
        }
        session.selection = TextStorage.Range(start: lineStart, end: lineEnd)
        session.cursorPosition = lineEnd
    }

    // MARK: - Theme / Font

    func updateTheme(_ theme: TerminalTheme) {
        applyTheme(theme)
        glyphCache.invalidateAll()
        needsRender = true
    }

    func updateFont(family: String, size: CGFloat) {
        layoutEngine.updateFont(family: family, size: size)
        glyphCache.invalidateAll()
        needsRender = true
    }

    private func applyTheme(_ theme: TerminalTheme) {
        themeColors = EditorLayoutEngine.ThemeColors(
            foreground: hexToColor(theme.foreground),
            background: hexToColor(theme.background),
            cursor: hexToColor(theme.cursor),
            selection: hexToColor(theme.selectionBackground, alpha: 128)
        )
        backgroundColor = hexToFloat4(theme.background)
    }

    private func hexToColor(_ hex: String, alpha: UInt8 = 255) -> SIMD4<UInt8> {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return SIMD4<UInt8>(204, 204, 204, alpha)
        }
        return SIMD4<UInt8>(
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
            alpha
        )
    }

    private func hexToFloat4(_ hex: String) -> SIMD4<Float> {
        let c = hexToColor(hex)
        return SIMD4<Float>(Float(c.x) / 255, Float(c.y) / 255, Float(c.z) / 255, 1.0)
    }

    // MARK: - IBActions (responder chain for Edit menu)

    @IBAction func copy(_ sender: Any?) {
        session?.copy()
    }

    @IBAction func paste(_ sender: Any?) {
        session?.paste()
    }

    @IBAction func cut(_ sender: Any?) {
        session?.cut()
    }

    @IBAction override func selectAll(_ sender: Any?) {
        session?.selectAll()
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let session else { return }
        markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)

        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        session.insertText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attrStr = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attrStr)
        } else if let str = string as? String {
            markedText = NSMutableAttributedString(string: str)
        }

        if markedText.length > 0 {
            _markedRange = NSRange(location: 0, length: markedText.length)
        } else {
            _markedRange = NSRange(location: NSNotFound, length: 0)
        }

        needsRender = true
    }

    func unmarkText() {
        markedText = NSMutableAttributedString()
        _markedRange = NSRange(location: NSNotFound, length: 0)
        needsRender = true
    }

    func selectedRange() -> NSRange {
        guard let sel = session?.selection?.normalized, !sel.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        // Approximate: return column range on first line
        return NSRange(location: sel.start.column, length: sel.end.column - sel.start.column)
    }

    func markedRange() -> NSRange {
        return _markedRange
    }

    func hasMarkedText() -> Bool {
        return markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        let viewRect = NSRect(x: 0, y: bounds.height - layoutEngine.lineHeight, width: 200, height: layoutEngine.lineHeight)
        return window.convertToScreen(convert(viewRect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        return NSNotFound
    }
}
