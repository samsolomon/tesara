import CoreGraphics
import CoreText
import Foundation

/// Lays out visible lines via CTLine, builds glyph and rect instances for rendering.
/// Supports word wrap via a two-pass layout: (1) wrap count pass, (2) visible line layout.
@MainActor
final class EditorLayoutEngine {

    struct LayoutLine {
        let lineIndex: Int       // storage line
        let wrapIndex: Int       // 0 = first visual line of this storage line
        let stringOffset: Int    // UTF-16 offset where this visual line begins in storage line
        let ctLine: CTLine
        let origin: CGPoint      // screen position (top-left of line)
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat
    }

    struct ThemeColors {
        var foreground: SIMD4<UInt8>
        var background: SIMD4<UInt8>
        var selection: SIMD4<UInt8>
    }

    struct CursorConfig {
        var style: CursorStyle
        var barWidth: Double
        var rounded: Bool
        var color: SIMD4<UInt8>
        var glowRadius: Double = 0
        var glowOpacity: Double = 0
    }

    private(set) var font: CTFont
    private(set) var lineHeight: CGFloat
    private(set) var visualLineMap = VisualLineMap()

    init(fontFamily: String, fontSize: CGFloat) {
        let font = CTFontCreateWithName(fontFamily as CFString, fontSize, nil)
        self.font = font
        self.lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    func updateFont(family: String, size: CGFloat) {
        let newFont = CTFontCreateWithName(family as CFString, size, nil)
        self.font = newFont
        self.lineHeight = ceil(CTFontGetAscent(newFont) + CTFontGetDescent(newFont) + CTFontGetLeading(newFont))
        self.rasterFont = nil
        self.rasterFontScale = 0
    }

    // MARK: - Visual Line Map

    struct VisualLineMap {
        private(set) var wrapCounts: [Int] = []
        private(set) var totalVisualLines: Int = 0
        private(set) var prefixSums: [Int] = []  // prefixSums[i] = sum of wrapCounts[0..<i]

        mutating func recomputeAll(lines: [String], font: CTFont, width: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            wrapCounts = []
            wrapCounts.reserveCapacity(lines.count)

            for content in lines {
                let count = countWraps(content: content, attributes: attributes, width: width)
                wrapCounts.append(count)
            }

            rebuildPrefixSums()
        }

        mutating func recomputeLine(_ lineIndex: Int, content: String, font: CTFont, width: CGFloat) {
            guard lineIndex >= 0, lineIndex < wrapCounts.count else { return }
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let newCount = countWraps(content: content, attributes: attributes, width: width)
            let delta = newCount - wrapCounts[lineIndex]
            guard delta != 0 else { return }
            wrapCounts[lineIndex] = newCount
            totalVisualLines += delta
            updatePrefixSums(from: lineIndex, delta: delta)
        }

        mutating func insertLine(at lineIndex: Int, content: String, font: CTFont, width: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let count = countWraps(content: content, attributes: attributes, width: width)
            wrapCounts.insert(count, at: lineIndex)
            // Insert requires full rebuild since all indices after shift
            rebuildPrefixSums()
        }

        func storagePosition(fromVisualLine visualLine: Int) -> (storageLine: Int, wrapIndex: Int) {
            // Binary search on prefix sums
            var lo = 0, hi = wrapCounts.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if prefixSums[mid + 1] <= visualLine {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            let wrapIdx = visualLine - prefixSums[lo]
            return (lo, wrapIdx)
        }

        func visualLine(fromStorageLine storageLine: Int, wrapIndex: Int = 0) -> Int {
            guard storageLine >= 0, storageLine < prefixSums.count else {
                return totalVisualLines
            }
            return prefixSums[storageLine] + wrapIndex
        }

        private mutating func rebuildPrefixSums() {
            prefixSums = [Int](repeating: 0, count: wrapCounts.count + 1)
            for i in 0..<wrapCounts.count {
                prefixSums[i + 1] = prefixSums[i] + wrapCounts[i]
            }
            totalVisualLines = prefixSums.last ?? 0
        }

        /// Incrementally update prefix sums from a single changed line.
        /// O(n - lineIndex) instead of O(n) for full rebuild.
        private mutating func updatePrefixSums(from lineIndex: Int, delta: Int) {
            for i in (lineIndex + 1)..<prefixSums.count {
                prefixSums[i] += delta
            }
        }

        private func countWraps(content: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> Int {
            guard !content.isEmpty, width > 0 else { return 1 }
            let attrStr = NSAttributedString(string: content, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            let length = CFAttributedStringGetLength(attrStr)
            var offset = 0
            var count = 0
            while offset < length {
                let breakIndex = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
                if breakIndex <= 0 { break }
                offset += breakIndex
                count += 1
            }
            return max(1, count)
        }
    }

    func recomputeWrapCounts(storage: TextStorage, viewportWidth: CGFloat) {
        let lines = (0..<storage.lineCount).map { storage.lineContent($0) }
        visualLineMap.recomputeAll(
            lines: lines,
            font: font,
            width: viewportWidth
        )
    }

    // MARK: - Layout

    func layoutVisibleLines(
        storage: TextStorage,
        scrollVisualLine: Int,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat,
        scale: CGFloat,
        wordWrap: Bool
    ) -> [LayoutLine] {
        if !wordWrap {
            return layoutVisibleLinesNoWrap(storage: storage, firstVisibleLine: scrollVisualLine, viewportHeight: viewportHeight, scale: scale)
        }

        var result: [LayoutLine] = []
        let scaledLineHeight = lineHeight * scale
        let maxVisualLines = Int(ceil(viewportHeight * scale / scaledLineHeight)) + 1
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        guard !visualLineMap.wrapCounts.isEmpty else {
            return layoutVisibleLinesNoWrap(storage: storage, firstVisibleLine: scrollVisualLine, viewportHeight: viewportHeight, scale: scale)
        }

        let (startStorageLine, startWrapOffset) = visualLineMap.storagePosition(fromVisualLine: scrollVisualLine)
        var currentVisualY = 0
        var storageLine = startStorageLine

        while currentVisualY < maxVisualLines && storageLine < storage.lineCount {
            let content = storage.lineContent(storageLine)
            let attrStr = NSAttributedString(string: content.isEmpty ? " " : content, attributes: attributes)
            let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
            let totalLen = CFAttributedStringGetLength(attrStr)

            var offset = 0
            var wrapIdx = 0

            // Advance to the starting wrap offset for the first storage line
            if storageLine == startStorageLine && startWrapOffset > 0 {
                for _ in 0..<startWrapOffset {
                    let breakLen = CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                    if breakLen <= 0 { break }
                    offset += breakLen
                    wrapIdx += 1
                }
            }

            while offset < totalLen && currentVisualY < maxVisualLines {
                let breakLen = CTTypesetterSuggestLineBreak(typesetter, offset, Double(viewportWidth))
                if breakLen <= 0 { break }
                let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: breakLen))

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)

                let y = CGFloat(currentVisualY) * scaledLineHeight

                result.append(LayoutLine(
                    lineIndex: storageLine,
                    wrapIndex: wrapIdx,
                    stringOffset: offset,
                    ctLine: ctLine,
                    origin: CGPoint(x: 0, y: y),
                    ascent: ascent * scale,
                    descent: descent * scale,
                    leading: leading * scale
                ))

                offset += breakLen
                wrapIdx += 1
                currentVisualY += 1
            }

            storageLine += 1
        }

        return result
    }

    /// No-wrap layout path (original behavior)
    private func layoutVisibleLinesNoWrap(
        storage: TextStorage,
        firstVisibleLine: Int,
        viewportHeight: CGFloat,
        scale: CGFloat
    ) -> [LayoutLine] {
        var result: [LayoutLine] = []
        let scaledLineHeight = lineHeight * scale
        let maxLines = Int(ceil(viewportHeight * scale / scaledLineHeight)) + 1

        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        for i in 0..<maxLines {
            let lineIndex = firstVisibleLine + i
            guard lineIndex < storage.lineCount else { break }

            let content = storage.lineContent(lineIndex)
            let attrString = NSAttributedString(string: content.isEmpty ? " " : content, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attrString)

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)

            let y = CGFloat(i) * scaledLineHeight

            result.append(LayoutLine(
                lineIndex: lineIndex,
                wrapIndex: 0,
                stringOffset: 0,
                ctLine: ctLine,
                origin: CGPoint(x: 0, y: y),
                ascent: ascent * scale,
                descent: descent * scale,
                leading: leading * scale
            ))
        }

        return result
    }

    // MARK: - Glyph Instances

    struct GlyphBuildResult {
        var monochrome: [EditorRenderer.GlyphInstance]
        var color: [EditorRenderer.GlyphInstance]
    }

    /// Cached font scaled for rasterization at the current display scale.
    private var rasterFont: CTFont?
    private var rasterFontScale: CGFloat = 0

    private func scaledRasterFont(scale: CGFloat) -> CTFont {
        if scale == rasterFontScale, let rasterFont { return rasterFont }
        let scaled = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * scale, nil, nil)
        rasterFont = scaled
        rasterFontScale = scale
        return scaled
    }

    func buildGlyphInstances(
        from layoutLines: [LayoutLine],
        cache: GlyphCache,
        scale: CGFloat,
        colors: ThemeColors,
        syntaxTokens: [Int: [SyntaxToken]]?,
        syntaxColors: SyntaxColorMap?
    ) -> GlyphBuildResult {
        var monoInstances: [EditorRenderer.GlyphInstance] = []
        var colorInstances: [EditorRenderer.GlyphInstance] = []

        // Rasterize glyphs at screen scale so atlas stores retina-resolution bitmaps
        let rasterFont = scale > 1 ? scaledRasterFont(scale: scale) : font

        for layoutLine in layoutLines {
            let runs = CTLineGetGlyphRuns(layoutLine.ctLine) as! [CTRun]
            let baselineY = layoutLine.origin.y + layoutLine.ascent

            // Get syntax tokens for this storage line
            let tokens = syntaxTokens?[layoutLine.lineIndex]

            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
                CTRunGetStringIndices(run, CFRange(location: 0, length: glyphCount), &stringIndices)

                for j in 0..<glyphCount {
                    let cached = cache.rasterize(glyph: glyphs[j], font: rasterFont)
                    guard cached.region.width > 0, cached.region.height > 0 else { continue }

                    let screenX = Float(positions[j].x * scale)
                    let screenY = Float(baselineY)

                    // Determine color from syntax tokens
                    var glyphColor = colors.foreground
                    if let tokens, let syntaxColors {
                        let storageCol = layoutLine.stringOffset + stringIndices[j]
                        glyphColor = colorForPosition(storageCol, tokens: tokens, colors: syntaxColors, fallback: colors.foreground)
                    }

                    let instance = EditorRenderer.GlyphInstance(
                        atlasPos: SIMD2<UInt16>(cached.region.x, cached.region.y),
                        atlasSize: SIMD2<UInt16>(cached.region.width, cached.region.height),
                        screenPos: SIMD2<Float>(screenX, screenY),
                        bearings: SIMD2<Int16>(cached.bearingX, cached.bearingY),
                        color: glyphColor
                    )

                    if cached.isColor {
                        colorInstances.append(instance)
                    } else {
                        monoInstances.append(instance)
                    }
                }
            }
        }

        return GlyphBuildResult(monochrome: monoInstances, color: colorInstances)
    }

    private func colorForPosition(_ position: Int, tokens: [SyntaxToken], colors: SyntaxColorMap, fallback: SIMD4<UInt8>) -> SIMD4<UInt8> {
        // Binary search — tokens are sorted by range start.
        var lo = 0, hi = tokens.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let token = tokens[mid]
            if position < token.range.lowerBound {
                hi = mid - 1
            } else if position >= token.range.upperBound {
                lo = mid + 1
            } else {
                return colors.color(for: token.kind)
            }
        }
        return fallback
    }

    // MARK: - Ghost Text (Autosuggestion)

    func buildGhostGlyphInstances(
        suffix: String,
        cursorPosition: TextStorage.Position,
        layoutLines: [LayoutLine],
        cache: GlyphCache,
        scale: CGFloat,
        foregroundColor: SIMD4<UInt8>,
        viewportWidth: CGFloat
    ) -> GlyphBuildResult {
        var monoInstances: [EditorRenderer.GlyphInstance] = []
        var colorInstances: [EditorRenderer.GlyphInstance] = []

        // Find the layout line containing the cursor
        guard let cursorLayoutLine = layoutLines.last(where: { $0.lineIndex == cursorPosition.line }) else {
            return GlyphBuildResult(monochrome: monoInstances, color: colorInstances)
        }

        // Compute cursor X position
        let cursorCol = cursorPosition.column - cursorLayoutLine.stringOffset
        let cursorX = CGFloat(offsetForColumn(cursorCol, in: cursorLayoutLine.ctLine, scale: scale))

        // Truncate suffix to remaining line width
        let remainingWidth = Double(viewportWidth * scale - cursorX) / Double(scale)
        guard remainingWidth > 0 else {
            return GlyphBuildResult(monochrome: monoInstances, color: colorInstances)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attrStr = NSAttributedString(string: suffix, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attrStr)
        let fitCount = CTTypesetterSuggestLineBreak(typesetter, 0, remainingWidth)
        guard fitCount > 0 else {
            return GlyphBuildResult(monochrome: monoInstances, color: colorInstances)
        }

        let ghostLine = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: fitCount))

        // Ghost color: foreground RGB with 30% alpha
        let ghostColor = SIMD4<UInt8>(foregroundColor.x, foregroundColor.y, foregroundColor.z, 77)

        let rasterFont = scale > 1 ? scaledRasterFont(scale: scale) : font
        let runs = CTLineGetGlyphRuns(ghostLine) as! [CTRun]
        let baselineY = cursorLayoutLine.origin.y + cursorLayoutLine.ascent

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

            for j in 0..<glyphCount {
                let cached = cache.rasterize(glyph: glyphs[j], font: rasterFont)
                guard cached.region.width > 0, cached.region.height > 0 else { continue }

                let screenX = Float(cursorX) + Float(positions[j].x * scale)
                let screenY = Float(baselineY)

                let instance = EditorRenderer.GlyphInstance(
                    atlasPos: SIMD2<UInt16>(cached.region.x, cached.region.y),
                    atlasSize: SIMD2<UInt16>(cached.region.width, cached.region.height),
                    screenPos: SIMD2<Float>(screenX, screenY),
                    bearings: SIMD2<Int16>(cached.bearingX, cached.bearingY),
                    color: ghostColor
                )

                if cached.isColor {
                    colorInstances.append(instance)
                } else {
                    monoInstances.append(instance)
                }
            }
        }

        return GlyphBuildResult(monochrome: monoInstances, color: colorInstances)
    }

    // MARK: - Rect Instances

    struct MarkedTextInfo {
        var line: Int
        var startColumn: Int
        var length: Int
    }

    func buildRectInstances(
        selection: TextStorage.Range?,
        cursorPos: TextStorage.Position,
        cursorVisible: Bool,
        cursorConfig: CursorConfig,
        markedText: MarkedTextInfo?,
        layoutLines: [LayoutLine],
        viewportWidth: CGFloat,
        scale: CGFloat,
        colors: ThemeColors,
        storage: TextStorage
    ) -> [EditorRenderer.RectInstance] {
        var rects: [EditorRenderer.RectInstance] = []
        let scaledLineHeight = lineHeight * scale

        // Selection rects (wrap-aware)
        if let sel = selection?.normalized, !sel.isEmpty {
            for layoutLine in layoutLines {
                let li = layoutLine.lineIndex
                guard li >= sel.start.line, li <= sel.end.line else { continue }

                let lineRange = CTLineGetStringRange(layoutLine.ctLine)
                let lineStart = layoutLine.stringOffset
                let lineEnd = lineStart + lineRange.length

                let selStart = (li == sel.start.line) ? sel.start.column : 0
                let selEnd = (li == sel.end.line) ? sel.end.column : storage.lineLength(li)

                let clampedStart = max(lineStart, selStart)
                let clampedEnd = min(lineEnd, selEnd)
                guard clampedStart < clampedEnd else {
                    // Full line selection extends beyond wrap boundaries
                    if li > sel.start.line && li < sel.end.line {
                        // Middle line of multi-line selection
                    } else if li == sel.start.line && selStart <= lineStart && selEnd >= lineEnd {
                        // Selection wraps around to next visual line
                    } else if li == sel.end.line && selEnd >= lineEnd && selStart <= lineStart {
                        // Same
                    } else {
                        continue
                    }
                    // Draw full-width selection for wrapped continuation
                    let fullWidth = CTLineGetTypographicBounds(layoutLine.ctLine, nil, nil, nil)
                    rects.append(EditorRenderer.RectInstance(
                        position: SIMD2<Float>(0, Float(layoutLine.origin.y)),
                        size: SIMD2<Float>(Float(fullWidth * scale) + Float(viewportWidth * scale), Float(scaledLineHeight)),
                        color: colors.selection
                    ))
                    continue
                }

                let startOffset = offsetForColumn(clampedStart - lineStart, in: layoutLine.ctLine, scale: scale)
                let endOffset: Float
                if clampedEnd >= lineEnd && li < sel.end.line {
                    // Extends to end of visual line and more
                    let lineWidth = CTLineGetTypographicBounds(layoutLine.ctLine, nil, nil, nil)
                    endOffset = Float(lineWidth * scale) + Float(viewportWidth * scale)
                } else {
                    endOffset = offsetForColumn(clampedEnd - lineStart, in: layoutLine.ctLine, scale: scale)
                }

                if endOffset > startOffset {
                    rects.append(EditorRenderer.RectInstance(
                        position: SIMD2<Float>(startOffset, Float(layoutLine.origin.y)),
                        size: SIMD2<Float>(endOffset - startOffset, Float(scaledLineHeight)),
                        color: colors.selection
                    ))
                }
            }
        }

        // IME marked text underline
        if let marked = markedText, marked.length > 0 {
            for layoutLine in layoutLines where layoutLine.lineIndex == marked.line && layoutLine.wrapIndex == 0 {
                let startX = offsetForColumn(marked.startColumn, in: layoutLine.ctLine, scale: scale)
                let endX = offsetForColumn(marked.startColumn + marked.length, in: layoutLine.ctLine, scale: scale)
                let underlineHeight: Float = max(Float(1.0 * scale), 1.0)
                let underlineY = Float(layoutLine.origin.y + scaledLineHeight) - underlineHeight

                rects.append(EditorRenderer.RectInstance(
                    position: SIMD2<Float>(startX, underlineY),
                    size: SIMD2<Float>(endX - startX, underlineHeight),
                    color: colors.foreground
                ))
                break
            }
        }

        // Cursor rect (wrap-aware, style-aware)
        if cursorVisible {
            for layoutLine in layoutLines where layoutLine.lineIndex == cursorPos.line {
                let lineRange = CTLineGetStringRange(layoutLine.ctLine)
                let lineStart = layoutLine.stringOffset
                let lineEnd = lineStart + lineRange.length
                let cursorInRange = cursorPos.column >= lineStart && cursorPos.column <= lineEnd
                if !cursorInRange { continue }

                let x = offsetForColumn(cursorPos.column - lineStart, in: layoutLine.ctLine, scale: scale)

                // Character-cell width (used by block & underline)
                let nextColX = offsetForColumn(cursorPos.column - lineStart + 1, in: layoutLine.ctLine, scale: scale)
                let charCellWidth: Float = {
                    let w = nextColX - x
                    return w > 0 ? w : max(Float(8.0 * scale), 1.0)
                }()

                let cursorWidth: Float
                let cursorHeight: Float
                let cursorY: Float
                let cornerRadius: Float

                switch cursorConfig.style {
                case .bar:
                    cursorWidth = max(Float(cursorConfig.barWidth * scale), 1.0)
                    cursorHeight = Float(scaledLineHeight)
                    cursorY = Float(layoutLine.origin.y)
                    cornerRadius = cursorConfig.rounded ? cursorWidth / 2.0 : 0

                case .block:
                    cursorWidth = charCellWidth
                    cursorHeight = Float(scaledLineHeight)
                    cursorY = Float(layoutLine.origin.y)
                    cornerRadius = cursorConfig.rounded ? min(2.0 * Float(scale), cursorWidth / 2.0) : 0

                case .underline:
                    cursorWidth = charCellWidth
                    cursorHeight = max(Float(2.0 * scale), 1.0)
                    cursorY = Float(layoutLine.origin.y + scaledLineHeight) - cursorHeight
                    cornerRadius = 0
                }

                rects.append(EditorRenderer.RectInstance(
                    position: SIMD2<Float>(x, cursorY),
                    size: SIMD2<Float>(cursorWidth, cursorHeight),
                    color: cursorConfig.color,
                    cornerRadius: cornerRadius,
                    glowRadius: Float(cursorConfig.glowRadius * scale),
                    glowOpacity: Float(cursorConfig.glowOpacity)
                ))
                break
            }
        }

        return rects
    }

    // MARK: - Hit Testing

    func hitTest(point: CGPoint, in layoutLines: [LayoutLine], scale: CGFloat) -> TextStorage.Position {
        let scaledLineHeight = lineHeight * scale

        for layoutLine in layoutLines {
            let lineTop = layoutLine.origin.y
            let lineBottom = lineTop + scaledLineHeight

            if point.y >= lineTop && point.y < lineBottom {
                let scaledX = point.x / scale
                let index = CTLineGetStringIndexForPosition(layoutLine.ctLine, CGPoint(x: scaledX, y: 0))
                let column = max(0, index) + layoutLine.stringOffset
                return TextStorage.Position(line: layoutLine.lineIndex, column: column)
            }
        }

        // Below all lines: return end of last line
        if let last = layoutLines.last {
            let lineLen = CTLineGetStringRange(last.ctLine).length
            return TextStorage.Position(line: last.lineIndex, column: max(0, last.stringOffset + lineLen))
        }

        return TextStorage.Position(line: 0, column: 0)
    }

    // MARK: - Helpers

    private func offsetForColumn(_ column: Int, in ctLine: CTLine, scale: CGFloat) -> Float {
        let offset = CTLineGetOffsetForStringIndex(ctLine, column, nil)
        return Float(offset * scale)
    }
}
