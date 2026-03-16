import AppKit
import Metal
import QuartzCore

@MainActor protocol EditorViewDelegate: AnyObject {
    func editorView(_ editorView: EditorView, handleKeyDown event: NSEvent) -> Bool
    func editorView(_ editorView: EditorView, handleSpecialKey key: NSEvent.SpecialKey, mods: NSEvent.ModifierFlags) -> Bool
}

/// NSView hosting a Metal-rendered rich text editor.
/// Counterpart to GhosttySurfaceView for the editor pane type.
class EditorView: NSView, NSTextInputClient {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Public State

    weak var session: EditorSession?
    weak var delegate: EditorViewDelegate?
    private(set) var focused: Bool = false

    var lineHeight: CGFloat { layoutEngine.lineHeight }

    // MARK: - Rendering

    private var metalLayer: CAMetalLayer!
    private var renderer: EditorRenderer?
    private let glyphAtlas = GlyphAtlas()
    private let colorGlyphAtlas: GlyphAtlas
    private let glyphCache: GlyphCache
    private var layoutEngine: EditorLayoutEngine

    private var renderTimer: Timer?
    private var needsRender: Bool = true

    // MARK: - Scroll

    private var scrollOffsetVisualLine: Int = 0

    // MARK: - Cursor Blink

    private var cursorVisible: Bool = true
    private var cursorBlinkTimer: Timer?
    private var smoothBlinkEnabled: Bool = false
    private var smoothBlinkPhase: Double = 0.0

    // MARK: - Cursor Config

    private var cursorConfig = EditorLayoutEngine.CursorConfig(
        style: .bar,
        barWidth: 3.0,
        rounded: true,
        color: SIMD4<UInt8>(204, 204, 204, 255)
    )

    // MARK: - Theme Colors

    private var themeColors = EditorLayoutEngine.ThemeColors(
        foreground: SIMD4<UInt8>(204, 204, 204, 255),
        background: SIMD4<UInt8>(30, 30, 30, 255),
        selection: SIMD4<UInt8>(60, 90, 150, 128)
    )
    private var backgroundColor: SIMD4<Float> = SIMD4<Float>(30.0/255, 30.0/255, 30.0/255, 1.0)
    private var syntaxColors: SyntaxColorMap?

    // MARK: - Event Monitor

    private var eventMonitor: Any?

    // MARK: - IME

    private var markedText = NSMutableAttributedString()
    private var _markedRange = NSRange(location: NSNotFound, length: 0)

    // MARK: - Content Size

    private var contentSize: CGSize = .zero

    // MARK: - Scrollbar

    var scrollbarDisabled: Bool = false
    private var scrollbarOpacity: Float = 0.0
    private var scrollbarFadeTimer: Timer?

    // MARK: - Ghost Text

    var ghostSuffixProvider: (() -> String?)?
    private var cachedGhostSuffix: String?
    private var cachedGhostResult: EditorLayoutEngine.GlyphBuildResult?

    // MARK: - Word Wrap State

    private var lastLayoutWidth: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Init

    init(session: EditorSession, theme: TerminalTheme, fontFamily: String, fontSize: CGFloat, cursorConfig: EditorLayoutEngine.CursorConfig? = nil, cursorBlink: Bool = true) {
        self.colorGlyphAtlas = GlyphAtlas(size: 512, bytesPerPixel: 4)
        self.glyphCache = GlyphCache(atlas: glyphAtlas, colorAtlas: colorGlyphAtlas)
        self.layoutEngine = EditorLayoutEngine(fontFamily: fontFamily, fontSize: fontSize)

        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        self.session = session
        self.wantsLayer = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        applyTheme(theme)
        if let cursorConfig {
            self.cursorConfig = cursorConfig
        }

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
        if cursorBlink {
            startCursorBlink()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        renderTimer?.invalidate()
        cursorBlinkTimer?.invalidate()
        scrollbarFadeTimer?.invalidate()
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
        // Handle scrollbar fade animation
        if scrollbarOpacity > 0 && scrollbarFadeTimer == nil {
            // Fade is in progress
            scrollbarOpacity -= 0.05
            if scrollbarOpacity <= 0 {
                scrollbarOpacity = 0
            } else {
                needsRender = true
            }
        }

        // Smooth blink: advance phase and force continuous rendering
        if smoothBlinkEnabled && focused {
            smoothBlinkPhase += (2.0 * .pi) / (60.0 * 1.0) // 1-second full cycle at 60fps
            if smoothBlinkPhase > 2.0 * .pi { smoothBlinkPhase -= 2.0 * .pi }
            needsRender = true
        }

        guard needsRender else { return }
        needsRender = false
        renderFrame()
    }

    func setNeedsRender() {
        needsRender = true
        resetCursorBlink()
    }

    func documentDidChange() {
        guard let session else { return }
        cachedGhostSuffix = nil
        cachedGhostResult = nil

        if session.wordWrapEnabled {
            let viewportWidth = contentSize.width > 0 ? contentSize.width : bounds.width
            layoutEngine.recomputeWrapCounts(storage: session.storage, viewportWidth: viewportWidth)
            lastLayoutWidth = viewportWidth
        }

        let totalLines = session.wordWrapEnabled
            ? max(1, layoutEngine.visualLineMap.totalVisualLines)
            : max(1, session.storage.lineCount)
        scrollOffsetVisualLine = min(scrollOffsetVisualLine, totalLines - 1)
        setNeedsRender()
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

    func renderOneFrame() {
        needsRender = true
        renderFrame()
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

    // MARK: - Ensure Cursor Visible

    func ensureCursorVisible() {
        guard let session else { return }
        let cursorLine = session.cursorPosition.line
        let viewportHeight = contentSize.height > 0 ? contentSize.height : bounds.height
        let visibleLines = Int(max(1, viewportHeight / layoutEngine.lineHeight))

        if session.wordWrapEnabled {
            let visualLine = layoutEngine.visualLineMap.visualLine(fromStorageLine: cursorLine)
            if visualLine < scrollOffsetVisualLine {
                scrollOffsetVisualLine = visualLine
            } else if visualLine >= scrollOffsetVisualLine + visibleLines {
                scrollOffsetVisualLine = visualLine - visibleLines + 1
            }
        } else {
            if cursorLine < scrollOffsetVisualLine {
                scrollOffsetVisualLine = cursorLine
            } else if cursorLine >= scrollOffsetVisualLine + visibleLines {
                scrollOffsetVisualLine = cursorLine - visibleLines + 1
            }
        }
        needsRender = true
    }

    // MARK: - Render

    private func renderFrame() {
        guard let session, let renderer, let metalLayer else { return }
        guard let drawable = metalLayer.nextDrawable() else { return }

        let scale = metalLayer.contentsScale
        let viewport = contentSize.width > 0 ? contentSize : bounds.size
        let viewportWidth = viewport.width

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            scrollVisualLine: scrollOffsetVisualLine,
            viewportWidth: viewportWidth,
            viewportHeight: viewport.height,
            scale: scale,
            wordWrap: session.wordWrapEnabled
        )

        // Ensure syntax tokens cover visible lines
        if let highlighter = session.syntaxHighlighter, highlighter.isActive {
            let lastVisible = layoutLines.last?.lineIndex ?? 0
            highlighter.ensureTokenized(throughLine: lastVisible, storage: session.storage)
        }

        // Collect syntax tokens for visible lines
        var syntaxTokensByLine: [Int: [SyntaxToken]]?
        if let highlighter = session.syntaxHighlighter, highlighter.isActive {
            var tokenMap: [Int: [SyntaxToken]] = [:]
            for ll in layoutLines {
                if tokenMap[ll.lineIndex] == nil {
                    tokenMap[ll.lineIndex] = highlighter.tokens(forLine: ll.lineIndex)
                }
            }
            syntaxTokensByLine = tokenMap
        }

        var glyphResult = layoutEngine.buildGlyphInstances(
            from: layoutLines,
            cache: glyphCache,
            scale: scale,
            colors: themeColors,
            syntaxTokens: syntaxTokensByLine,
            syntaxColors: syntaxColors
        )

        // Ghost text (autosuggestion)
        let ghostSuffix = ghostSuffixProvider?()
        if let ghostSuffix, !ghostSuffix.isEmpty {
            let ghostResult: EditorLayoutEngine.GlyphBuildResult
            if ghostSuffix == cachedGhostSuffix, let cached = cachedGhostResult {
                ghostResult = cached
            } else {
                ghostResult = layoutEngine.buildGhostGlyphInstances(
                    suffix: ghostSuffix,
                    cursorPosition: session.cursorPosition,
                    layoutLines: layoutLines,
                    cache: glyphCache,
                    scale: scale,
                    foregroundColor: themeColors.foreground,
                    viewportWidth: viewport.width
                )
                cachedGhostSuffix = ghostSuffix
                cachedGhostResult = ghostResult
            }
            glyphResult.monochrome.append(contentsOf: ghostResult.monochrome)
            glyphResult.color.append(contentsOf: ghostResult.color)
        } else if cachedGhostSuffix != nil {
            cachedGhostSuffix = nil
            cachedGhostResult = nil
        }

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

        var rects = layoutEngine.buildRectInstances(
            selection: session.selection,
            cursorPos: session.cursorPosition,
            cursorVisible: cursorVisible && focused,
            cursorConfig: cursorConfig,
            markedText: markedTextInfo,
            layoutLines: layoutLines,
            viewportWidth: viewport.width,
            scale: scale,
            colors: themeColors,
            storage: session.storage
        )

        // Apply smooth blink opacity to cursor rect (always last when visible)
        if smoothBlinkEnabled && cursorVisible && focused && !rects.isEmpty {
            let opacity = Float(0.3 + 0.7 * ((sin(smoothBlinkPhase) + 1.0) / 2.0))
            let idx = rects.count - 1
            let c = rects[idx].color
            rects[idx].color = SIMD4<UInt8>(c.x, c.y, c.z, UInt8(Float(c.w) * opacity))
        }

        // Scrollbar overlay
        var overlayRects: [EditorRenderer.RectInstance] = []
        if scrollbarOpacity > 0 && !scrollbarDisabled {
            let totalLines: Int
            if session.wordWrapEnabled {
                totalLines = max(1, layoutEngine.visualLineMap.totalVisualLines)
            } else {
                totalLines = max(1, session.storage.lineCount)
            }
            let visibleLines = Int(max(1, viewport.height / layoutEngine.lineHeight))
            let viewportPx = Float(viewport.height * scale)

            let thumbRatio = Float(visibleLines) / Float(totalLines)
            let thumbHeight = max(20 * Float(scale), thumbRatio * viewportPx)
            let scrollRatio = Float(scrollOffsetVisualLine) / Float(max(1, totalLines - visibleLines))
            let thumbY = scrollRatio * (viewportPx - thumbHeight)

            let scrollbarWidth: Float = 6 * Float(scale)
            let scrollbarInset: Float = 2 * Float(scale)
            let scrollbarX = Float(viewport.width * scale) - scrollbarWidth - scrollbarInset

            let alphaU8 = UInt8(min(255, Float(255) * scrollbarOpacity * 0.5))
            overlayRects.append(EditorRenderer.RectInstance(
                position: SIMD2<Float>(scrollbarX, thumbY),
                size: SIMD2<Float>(scrollbarWidth, thumbHeight),
                color: SIMD4<UInt8>(200, 200, 200, alphaU8)
            ))
        }

        renderer.render(
            to: drawable,
            viewport: viewport,
            scale: scale,
            scrollOffset: .zero,
            rects: rects,
            glyphs: glyphResult.monochrome,
            colorGlyphs: glyphResult.color,
            backgroundColor: backgroundColor,
            atlas: glyphAtlas,
            colorAtlas: colorGlyphAtlas,
            overlayRects: overlayRects
        )
    }

    // MARK: - Size

    func sizeDidChange(_ size: CGSize) {
        contentSize = size
        cachedGhostSuffix = nil
        cachedGhostResult = nil
        guard let metalLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scaledSize = CGSize(
            width: size.width * metalLayer.contentsScale,
            height: size.height * metalLayer.contentsScale
        )
        metalLayer.drawableSize = scaledSize
        CATransaction.commit()

        // Recompute wrap counts on resize
        if let session, session.wordWrapEnabled {
            layoutEngine.recomputeWrapCounts(storage: session.storage, viewportWidth: size.width)
            lastLayoutWidth = size.width
        }

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
        if let delegate, delegate.editorView(self, handleKeyDown: event) {
            return
        }

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
            ensureCursorVisible()
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
            ensureCursorVisible()
            return true
        case "c":
            session.copy()
            return true
        case "v":
            session.paste()
            ensureCursorVisible()
            return true
        case "x":
            session.cut()
            ensureCursorVisible()
            return true
        default:
            return false
        }
    }

    private func handleSpecialKey(_ key: NSEvent.SpecialKey, mods: NSEvent.ModifierFlags, session: EditorSession) {
        if let delegate, delegate.editorView(self, handleSpecialKey: key, mods: mods) {
            return
        }
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
        ensureCursorVisible()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard let session else { return }
        let location = convert(event.locationInWindow, from: nil)
        let scale = metalLayer?.contentsScale ?? 1.0
        let viewportHeight = contentSize.height > 0 ? contentSize.height : bounds.height

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            scrollVisualLine: scrollOffsetVisualLine,
            viewportWidth: contentSize.width > 0 ? contentSize.width : bounds.width,
            viewportHeight: viewportHeight,
            scale: scale,
            wordWrap: session.wordWrapEnabled
        )

        let pos = layoutEngine.hitTest(point: CGPoint(x: location.x * scale, y: (viewportHeight - location.y) * scale), in: layoutLines, scale: scale)
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
        let viewportHeight = contentSize.height > 0 ? contentSize.height : bounds.height

        let layoutLines = layoutEngine.layoutVisibleLines(
            storage: session.storage,
            scrollVisualLine: scrollOffsetVisualLine,
            viewportWidth: contentSize.width > 0 ? contentSize.width : bounds.width,
            viewportHeight: viewportHeight,
            scale: scale,
            wordWrap: session.wordWrapEnabled
        )

        let pos = layoutEngine.hitTest(point: CGPoint(x: location.x * scale, y: (viewportHeight - location.y) * scale), in: layoutLines, scale: scale)
        let anchor = session.selection?.start ?? session.cursorPosition
        session.selection = TextStorage.Range(start: anchor, end: pos)
        session.cursorPosition = pos
        needsRender = true
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        let deltaLines = -event.scrollingDeltaY / layoutEngine.lineHeight

        if abs(deltaLines) >= 1 {
            let lineDelta = Int(deltaLines)
            scrollOffsetVisualLine = max(0, scrollOffsetVisualLine + lineDelta)
        }

        onScrollActivity()
        needsRender = true
    }

    private func scrollPageUp() {
        let visibleLines = Int(max(1, (contentSize.height > 0 ? contentSize.height : bounds.height) / layoutEngine.lineHeight))
        scrollOffsetVisualLine = max(0, scrollOffsetVisualLine - visibleLines)
        onScrollActivity()
        needsRender = true
    }

    private func scrollPageDown() {
        guard let session else { return }
        let visibleLines = Int(max(1, (contentSize.height > 0 ? contentSize.height : bounds.height) / layoutEngine.lineHeight))
        let totalLines: Int
        if session.wordWrapEnabled {
            totalLines = layoutEngine.visualLineMap.totalVisualLines
        } else {
            totalLines = session.storage.lineCount
        }
        scrollOffsetVisualLine = min(max(0, totalLines - 1), scrollOffsetVisualLine + visibleLines)
        onScrollActivity()
        needsRender = true
    }

    // MARK: - Scrollbar

    private func onScrollActivity() {
        scrollbarOpacity = 1.0
        scrollbarFadeTimer?.invalidate()
        scrollbarFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.beginScrollbarFade()
        }
        needsRender = true
    }

    private func beginScrollbarFade() {
        scrollbarFadeTimer = nil
        // Fade handled in renderTimerFired
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
        cachedGhostSuffix = nil
        cachedGhostResult = nil
        needsRender = true
    }

    func updateFont(family: String, size: CGFloat) {
        layoutEngine.updateFont(family: family, size: size)
        glyphCache.invalidateAll()
        cachedGhostSuffix = nil
        cachedGhostResult = nil
        if let session, session.wordWrapEnabled {
            layoutEngine.recomputeWrapCounts(storage: session.storage, viewportWidth: contentSize.width > 0 ? contentSize.width : bounds.width)
        }
        needsRender = true
    }

#if DEBUG
    func totalVisualLinesForTesting() -> Int {
        layoutEngine.visualLineMap.totalVisualLines
    }
#endif

    func updateCursorConfig(_ config: EditorLayoutEngine.CursorConfig, blink: Bool, smoothBlink: Bool = false) {
        cursorConfig = config
        smoothBlinkEnabled = smoothBlink && blink

        if smoothBlinkEnabled {
            // Smooth blink: stop the hard blink timer, cursor stays "visible" (opacity modulated in renderFrame)
            cursorBlinkTimer?.invalidate()
            cursorBlinkTimer = nil
            cursorVisible = true
        } else if blink {
            if cursorBlinkTimer == nil {
                startCursorBlink()
            }
        } else {
            cursorBlinkTimer?.invalidate()
            cursorBlinkTimer = nil
            cursorVisible = true
        }

        needsRender = true
    }

    private func applyTheme(_ theme: TerminalTheme) {
        themeColors = EditorLayoutEngine.ThemeColors(
            foreground: hexToColorU8(theme.foreground),
            background: hexToColorU8(theme.background),
            selection: hexToColorU8(theme.selectionBackground, alpha: 128)
        )
        cursorConfig.color = hexToColorU8(theme.cursor)
        let bg = hexToColorU8(theme.background)
        backgroundColor = SIMD4<Float>(Float(bg.x) / 255, Float(bg.y) / 255, Float(bg.z) / 255, 1.0)
        syntaxColors = SyntaxColorMap(theme: theme)
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

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .textArea
    }

    override func accessibilityHelp() -> String? {
        return "Editor input area"
    }

    override func accessibilityValue() -> Any? {
        return session?.storage.entireString()
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        guard let session else {
            return NSRange(location: 0, length: 0)
        }
        guard let sel = session.selection?.normalized, !sel.isEmpty else {
            // No selection — report cursor as zero-length range at flat document offset
            let offset = utf16Offset(for: session.cursorPosition, in: session.storage)
            return NSRange(location: offset, length: 0)
        }
        let startOffset = utf16Offset(for: sel.start, in: session.storage)
        let endOffset = utf16Offset(for: sel.end, in: session.storage)
        return NSRange(location: startOffset, length: endOffset - startOffset)
    }

    override func accessibilitySelectedText() -> String? {
        return session?.selectedText()
    }

    override func accessibilityNumberOfCharacters() -> Int {
        return session?.storage.totalUTF16Length() ?? 0
    }

    override func accessibilityVisibleCharacterRange() -> NSRange {
        let count = session?.storage.totalUTF16Length() ?? 0
        return NSRange(location: 0, length: count)
    }

    /// Convert a TextStorage.Position to a flat UTF-16 offset across the entire document.
    private func utf16Offset(for pos: TextStorage.Position, in storage: TextStorage) -> Int {
        var offset = 0
        for i in 0..<pos.line {
            offset += storage.lineLength(i) + 1 // +1 for "\n" (one UTF-16 code unit)
        }
        offset += pos.column
        return offset
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
        ensureCursorVisible()
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

    // MARK: - Suppress Character Palette

    @objc override func orderFrontCharacterPalette(_ sender: Any?) {
        // No-op: prevent fn/Globe from opening the emoji picker
    }
}
