import CoreGraphics
import CoreText
import Foundation

/// Lays out visible lines via CTLine, builds glyph and rect instances for rendering.
@MainActor
final class EditorLayoutEngine {

    struct LayoutLine {
        let lineIndex: Int
        let ctLine: CTLine
        let origin: CGPoint  // screen position (top-left of line)
        let ascent: CGFloat
        let descent: CGFloat
        let leading: CGFloat
    }

    struct ThemeColors {
        var foreground: SIMD4<UInt8>
        var background: SIMD4<UInt8>
        var cursor: SIMD4<UInt8>
        var selection: SIMD4<UInt8>
    }

    private(set) var font: CTFont
    private(set) var lineHeight: CGFloat

    init(fontFamily: String, fontSize: CGFloat) {
        let font = CTFontCreateWithName(fontFamily as CFString, fontSize, nil)
        self.font = font
        self.lineHeight = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
    }

    func updateFont(family: String, size: CGFloat) {
        let newFont = CTFontCreateWithName(family as CFString, size, nil)
        self.font = newFont
        self.lineHeight = ceil(CTFontGetAscent(newFont) + CTFontGetDescent(newFont) + CTFontGetLeading(newFont))
    }

    // MARK: - Layout

    func layoutVisibleLines(
        storage: TextStorage,
        firstVisibleLine: Int,
        viewportHeight: CGFloat,
        scale: CGFloat
    ) -> [LayoutLine] {
        var result: [LayoutLine] = []
        let scaledLineHeight = lineHeight * scale
        let maxLines = Int(ceil(viewportHeight * scale / scaledLineHeight)) + 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]

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
            let origin = CGPoint(x: 0, y: y)

            result.append(LayoutLine(
                lineIndex: lineIndex,
                ctLine: ctLine,
                origin: origin,
                ascent: ascent * scale,
                descent: descent * scale,
                leading: leading * scale
            ))
        }

        return result
    }

    // MARK: - Glyph Instances

    func buildGlyphInstances(
        from layoutLines: [LayoutLine],
        cache: GlyphCache,
        scale: CGFloat,
        colors: ThemeColors
    ) -> [EditorRenderer.GlyphInstance] {
        var instances: [EditorRenderer.GlyphInstance] = []

        for layoutLine in layoutLines {
            let runs = CTLineGetGlyphRuns(layoutLine.ctLine) as! [CTRun]
            let baselineY = layoutLine.origin.y + layoutLine.ascent

            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                guard glyphCount > 0 else { continue }

                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)

                for j in 0..<glyphCount {
                    let cached = cache.rasterize(glyph: glyphs[j], font: font)
                    guard cached.region.width > 0, cached.region.height > 0 else { continue }

                    let screenX = Float(positions[j].x * scale)
                    let screenY = Float(baselineY)

                    instances.append(EditorRenderer.GlyphInstance(
                        atlasPos: SIMD2<UInt16>(cached.region.x, cached.region.y),
                        atlasSize: SIMD2<UInt16>(cached.region.width, cached.region.height),
                        screenPos: SIMD2<Float>(screenX, screenY),
                        bearings: SIMD2<Int16>(cached.bearingX, cached.bearingY),
                        color: colors.foreground
                    ))
                }
            }
        }

        return instances
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
        markedText: MarkedTextInfo?,
        layoutLines: [LayoutLine],
        viewportWidth: CGFloat,
        scale: CGFloat,
        colors: ThemeColors
    ) -> [EditorRenderer.RectInstance] {
        var rects: [EditorRenderer.RectInstance] = []
        let scaledLineHeight = lineHeight * scale

        // Selection rects
        if let sel = selection?.normalized, !sel.isEmpty {
            for layoutLine in layoutLines {
                let li = layoutLine.lineIndex
                guard li >= sel.start.line, li <= sel.end.line else { continue }

                let lineLen = CTLineGetTypographicBounds(layoutLine.ctLine, nil, nil, nil)
                let startCol = li == sel.start.line ? sel.start.column : 0
                let endCol = li == sel.end.line ? sel.end.column : Int.max

                let startOffset = offsetForColumn(startCol, in: layoutLine.ctLine, scale: scale)
                let endOffset: Float
                if endCol == Int.max {
                    endOffset = Float(lineLen * scale) + Float(viewportWidth * scale)
                } else {
                    endOffset = offsetForColumn(endCol, in: layoutLine.ctLine, scale: scale)
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
            for layoutLine in layoutLines where layoutLine.lineIndex == marked.line {
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

        // Cursor rect (thin line)
        if cursorVisible {
            for layoutLine in layoutLines where layoutLine.lineIndex == cursorPos.line {
                let x = offsetForColumn(cursorPos.column, in: layoutLine.ctLine, scale: scale)
                let cursorWidth: Float = max(Float(2.0 * scale), 1.0)
                rects.append(EditorRenderer.RectInstance(
                    position: SIMD2<Float>(x, Float(layoutLine.origin.y)),
                    size: SIMD2<Float>(cursorWidth, Float(scaledLineHeight)),
                    color: colors.cursor
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
                let column = max(0, index)
                return TextStorage.Position(line: layoutLine.lineIndex, column: column)
            }
        }

        // Below all lines: return end of last line
        if let last = layoutLines.last {
            let lineLen = CTLineGetStringRange(last.ctLine).length
            return TextStorage.Position(line: last.lineIndex, column: max(0, lineLen))
        }

        return TextStorage.Position(line: 0, column: 0)
    }

    // MARK: - Helpers

    private func offsetForColumn(_ column: Int, in ctLine: CTLine, scale: CGFloat) -> Float {
        let offset = CTLineGetOffsetForStringIndex(ctLine, column, nil)
        return Float(offset * scale)
    }
}
