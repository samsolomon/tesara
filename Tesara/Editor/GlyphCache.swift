import CoreGraphics
import CoreText
import Foundation

/// Rasterizes glyphs via CTFont into a GlyphAtlas, caching results.
/// Supports dual atlases: grayscale for text, BGRA for color emoji.
final class GlyphCache {

    struct GlyphKey: Hashable {
        let glyph: CGGlyph
        let fontHash: Int
        let subpixelBin: UInt8  // 0-3 for non-Retina, 0 for Retina
    }

    struct CachedGlyph {
        let region: GlyphAtlas.Region
        let bearingX: Int16
        let bearingY: Int16
        /// Sub-pixel baseline correction: Float(bearingY) − exact bearing.
        /// Add to screenPos.y so the shader's integer subtraction lands on the true baseline.
        let baselineOffset: Float
        let advance: Float
        let isPlaceholder: Bool
        let isColor: Bool
    }

    private var cache: [GlyphKey: CachedGlyph] = [:]
    private let monoAtlas: GlyphAtlas
    private let colorAtlas: GlyphAtlas

    /// Cache per-font color glyph detection (font hash → has color tables)
    private var fontColorCache: [Int: Bool] = [:]

    init(atlas: GlyphAtlas, colorAtlas: GlyphAtlas) {
        self.monoAtlas = atlas
        self.colorAtlas = colorAtlas
    }

    func lookup(glyph: CGGlyph, font: CTFont, subpixelOffset: CGFloat = 0) -> CachedGlyph? {
        let key = makeKey(glyph: glyph, font: font, subpixelOffset: subpixelOffset)
        return cache[key]
    }

    func rasterize(glyph: CGGlyph, font: CTFont, subpixelOffset: CGFloat = 0) -> CachedGlyph {
        let key = makeKey(glyph: glyph, font: font, subpixelOffset: subpixelOffset)
        if let cached = cache[key] { return cached }

        // Check for color glyph (emoji)
        if isColorGlyph(font: font) {
            let colorResult = rasterizeColorGlyph(glyph: glyph, font: font, key: key)
            cache[key] = colorResult
            return colorResult
        }

        // Get glyph metrics
        var glyphRef = glyph
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphRef, &boundingRect, 1)

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyphRef, &advance, 1)

        // Add padding for rasterization
        let padding: Int = 1
        let width = Int(ceil(boundingRect.width)) + padding * 2
        let height = Int(ceil(boundingRect.height)) + padding * 2

        guard width > 0, height > 0 else {
            // Zero-size glyph (e.g., space) — cache with empty region
            let empty = CachedGlyph(
                region: GlyphAtlas.Region(x: 0, y: 0, width: 0, height: 0),
                bearingX: 0,
                bearingY: 0,
                baselineOffset: 0,
                advance: Float(advance.width),
                isPlaceholder: false,
                isColor: false
            )
            cache[key] = empty
            return empty
        }

        // Allocate in mono atlas, growing if needed
        var region = monoAtlas.allocate(width: width, height: height)
        if region == nil {
            monoAtlas.grow()
            region = monoAtlas.allocate(width: width, height: height)
        }

        guard let region else {
            // Fallback: return empty
            let empty = CachedGlyph(
                region: GlyphAtlas.Region(x: 0, y: 0, width: 0, height: 0),
                bearingX: 0,
                bearingY: 0,
                baselineOffset: 0,
                advance: Float(advance.width),
                isPlaceholder: false,
                isColor: false
            )
            cache[key] = empty
            return empty
        }

        // Rasterize glyph into grayscale bitmap
        let bitmapData = rasterizeGrayscaleGlyph(
            glyph: glyph,
            font: font,
            width: width,
            height: height,
            bearingX: boundingRect.origin.x,
            bearingY: boundingRect.origin.y,
            subpixelOffset: subpixelOffset,
            padding: padding
        )

        monoAtlas.write(data: bitmapData, to: region)

        let byMetrics = bearingYMetrics(boundingRect: boundingRect, bitmapHeight: height, padding: padding)

        let cached = CachedGlyph(
            region: region,
            bearingX: Int16(floor(boundingRect.origin.x)) - Int16(padding),
            bearingY: byMetrics.bearingY,
            baselineOffset: byMetrics.baselineOffset,
            advance: Float(advance.width),
            isPlaceholder: false,
            isColor: false
        )
        cache[key] = cached
        return cached
    }

    func isColorGlyph(font: CTFont) -> Bool {
        let fontHash = Int(bitPattern: ObjectIdentifier(font))
        if let cached = fontColorCache[fontHash] { return cached }
        let sbix = CTFontCopyTable(font, CTFontTableTag(kCTFontTableSbix), [])
        let colr = CTFontCopyTable(font, CTFontTableTag(kCTFontTableCOLR), [])
        let isColor = sbix != nil || colr != nil
        fontColorCache[fontHash] = isColor
        return isColor
    }

    func invalidateAll() {
        cache.removeAll()
        fontColorCache.removeAll()
        monoAtlas.reset()
        colorAtlas.reset()
    }

    /// Compute integer bearingY and sub-pixel baseline correction from glyph bounding rect.
    private func bearingYMetrics(boundingRect: CGRect, bitmapHeight: Int, padding: Int) -> (bearingY: Int16, baselineOffset: Float) {
        let drawY = -boundingRect.origin.y + CGFloat(padding)
        let exactBearingY = Float(CGFloat(bitmapHeight) - drawY)
        let bearingYInt = Int16(ceil(boundingRect.origin.y + boundingRect.height)) + Int16(padding)
        return (bearingYInt, Float(bearingYInt) - exactBearingY)
    }

    // MARK: - Private

    private func makeKey(glyph: CGGlyph, font: CTFont, subpixelOffset: CGFloat) -> GlyphKey {
        let fontHash = Int(bitPattern: ObjectIdentifier(font))
        // Quantize subpixel offset into 4 bins
        let bin = UInt8(((subpixelOffset - floor(subpixelOffset)) * 4).rounded(.down).clamped(to: 0...3))
        return GlyphKey(glyph: glyph, fontHash: fontHash, subpixelBin: bin)
    }

    private func rasterizeColorGlyph(glyph: CGGlyph, font: CTFont, key: GlyphKey) -> CachedGlyph {
        var glyphRef = glyph
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphRef, &boundingRect, 1)

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &glyphRef, &advance, 1)

        let padding: Int = 1
        let width = max(Int(ceil(boundingRect.width)) + padding * 2, 1)
        let height = max(Int(ceil(boundingRect.height)) + padding * 2, 1)

        // Allocate in color atlas
        var region = colorAtlas.allocate(width: width, height: height)
        if region == nil {
            colorAtlas.grow()
            region = colorAtlas.allocate(width: width, height: height)
        }

        guard let region else {
            return CachedGlyph(
                region: GlyphAtlas.Region(x: 0, y: 0, width: 0, height: 0),
                bearingX: 0,
                bearingY: 0,
                baselineOffset: 0,
                advance: Float(advance.width),
                isPlaceholder: true,
                isColor: true
            )
        }

        // Rasterize into BGRA bitmap
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        pixelData.withUnsafeMutableBufferPointer { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let drawX = -boundingRect.origin.x + CGFloat(padding)
            let drawY = -boundingRect.origin.y + CGFloat(padding)

            var position = CGPoint(x: drawX, y: drawY)
            var glyphRef = glyph
            CTFontDrawGlyphs(font, &glyphRef, &position, 1, context)
        }

        colorAtlas.write(data: pixelData, to: region)

        let colorByMetrics = bearingYMetrics(boundingRect: boundingRect, bitmapHeight: height, padding: padding)

        return CachedGlyph(
            region: region,
            bearingX: Int16(floor(boundingRect.origin.x)) - Int16(padding),
            bearingY: colorByMetrics.bearingY,
            baselineOffset: colorByMetrics.baselineOffset,
            advance: Float(advance.width),
            isPlaceholder: false,
            isColor: true
        )
    }

    private func rasterizeGrayscaleGlyph(
        glyph: CGGlyph,
        font: CTFont,
        width: Int,
        height: Int,
        bearingX: CGFloat,
        bearingY: CGFloat,
        subpixelOffset: CGFloat,
        padding: Int
    ) -> [UInt8] {
        let bytesPerRow = width
        var pixelData = [UInt8](repeating: 0, count: width * height)

        pixelData.withUnsafeMutableBufferPointer { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))

            // Position glyph so its origin aligns with the bitmap
            let drawX = -bearingX + CGFloat(padding) + subpixelOffset
            let drawY = -bearingY + CGFloat(padding)

            var position = CGPoint(x: drawX, y: drawY)
            var glyphRef = glyph
            CTFontDrawGlyphs(font, &glyphRef, &position, 1, context)
        }

        return pixelData
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
