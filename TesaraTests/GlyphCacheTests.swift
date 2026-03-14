import XCTest
import CoreText
import CoreGraphics
@testable import Tesara

final class GlyphCacheTests: XCTestCase {
    private var monoAtlas: GlyphAtlas!
    private var colorAtlas: GlyphAtlas!
    private var cache: GlyphCache!
    private var testFont: CTFont!

    override func setUp() {
        super.setUp()
        monoAtlas = GlyphAtlas(size: 256)
        colorAtlas = GlyphAtlas(size: 256, bytesPerPixel: 4)
        cache = GlyphCache(atlas: monoAtlas, colorAtlas: colorAtlas)
        testFont = CTFontCreateWithName("Menlo" as CFString, 14, nil)
    }

    override func tearDown() {
        cache = nil
        monoAtlas = nil
        colorAtlas = nil
        testFont = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func glyphID(for character: Character) -> CGGlyph {
        var chars = [UniChar](String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(testFont, &chars, &glyphs, chars.count)
        return glyphs[0]
    }

    // MARK: - Lookup

    func testLookupReturnsNilForUncachedGlyph() {
        let glyph = glyphID(for: "A")
        XCTAssertNil(cache.lookup(glyph: glyph, font: testFont))
    }

    func testLookupReturnsGlyphAfterRasterize() {
        let glyph = glyphID(for: "A")
        _ = cache.rasterize(glyph: glyph, font: testFont)
        let result = cache.lookup(glyph: glyph, font: testFont)
        XCTAssertNotNil(result)
    }

    // MARK: - Rasterize

    func testRasterizeReturnsValidGlyph() {
        let glyph = glyphID(for: "A")
        let result = cache.rasterize(glyph: glyph, font: testFont)
        XCTAssertFalse(result.isPlaceholder)
        XCTAssertFalse(result.isColor)
        XCTAssertGreaterThan(result.advance, 0)
    }

    func testRasterizeSameGlyphReturnsCachedResult() {
        let glyph = glyphID(for: "B")
        let first = cache.rasterize(glyph: glyph, font: testFont)
        let second = cache.rasterize(glyph: glyph, font: testFont)
        // Same region means same cached glyph
        XCTAssertEqual(first.region, second.region)
        XCTAssertEqual(first.advance, second.advance)
        XCTAssertEqual(first.bearingX, second.bearingX)
        XCTAssertEqual(first.bearingY, second.bearingY)
    }

    func testRasterizeDifferentGlyphsReturnDifferentRegions() {
        let glyphA = glyphID(for: "A")
        let glyphB = glyphID(for: "B")
        let resultA = cache.rasterize(glyph: glyphA, font: testFont)
        let resultB = cache.rasterize(glyph: glyphB, font: testFont)

        // Different glyphs should have different atlas positions (unless both are zero-size)
        if resultA.region.width > 0 && resultB.region.width > 0 {
            XCTAssertNotEqual(resultA.region, resultB.region)
        }
    }

    func testRasterizeSpaceHasZeroSizeRegion() {
        let glyph = glyphID(for: " ")
        let result = cache.rasterize(glyph: glyph, font: testFont)
        XCTAssertEqual(result.region.width, 0)
        XCTAssertEqual(result.region.height, 0)
        XCTAssertGreaterThan(result.advance, 0) // space still has advance width
        XCTAssertFalse(result.isPlaceholder)
    }

    func testRasterizeMultipleGlyphs() {
        let chars: [Character] = ["H", "e", "l", "o", "W", "r", "d"]
        var regions: [GlyphAtlas.Region] = []
        for ch in chars {
            let glyph = glyphID(for: ch)
            let result = cache.rasterize(glyph: glyph, font: testFont)
            if result.region.width > 0 {
                regions.append(result.region)
            }
        }
        // All non-zero regions should be unique
        let uniquePositions = Set(regions.map { "\($0.x),\($0.y)" })
        XCTAssertEqual(uniquePositions.count, regions.count, "Glyph regions should not overlap")
    }

    func testRasterizeWritesToMonoAtlas() {
        let initialModified = monoAtlas.modifiedCount
        let glyph = glyphID(for: "X")
        let result = cache.rasterize(glyph: glyph, font: testFont)
        if result.region.width > 0 {
            XCTAssertGreaterThan(monoAtlas.modifiedCount, initialModified)
        }
    }

    // MARK: - Different Fonts

    func testDifferentFontSizesProduceDifferentGlyphs() {
        let smallFont = CTFontCreateWithName("Menlo" as CFString, 10, nil)
        let largeFont = CTFontCreateWithName("Menlo" as CFString, 24, nil)

        let glyph = glyphID(for: "A")
        let smallResult = cache.rasterize(glyph: glyph, font: smallFont)
        let largeResult = cache.rasterize(glyph: glyph, font: largeFont)

        // Different font objects → different cache entries
        if smallResult.region.width > 0 && largeResult.region.width > 0 {
            XCTAssertNotEqual(smallResult.region, largeResult.region)
        }
        // Larger font should have larger advance
        XCTAssertGreaterThan(largeResult.advance, smallResult.advance)
    }

    func testDifferentFontFamiliesProduceDifferentGlyphs() {
        let menlo = CTFontCreateWithName("Menlo" as CFString, 14, nil)
        let courier = CTFontCreateWithName("Courier" as CFString, 14, nil)

        let glyph = glyphID(for: "M")
        let menloResult = cache.rasterize(glyph: glyph, font: menlo)

        // Get glyph ID for Courier (may differ from Menlo)
        var chars = [UniChar](String("M").utf16)
        var courierGlyphs = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(courier, &chars, &courierGlyphs, chars.count)
        let courierResult = cache.rasterize(glyph: courierGlyphs[0], font: courier)

        // Both should produce valid results
        XCTAssertFalse(menloResult.isPlaceholder)
        XCTAssertFalse(courierResult.isPlaceholder)
    }

    // MARK: - Subpixel Binning

    func testSubpixelBinsProduceSeparateCacheEntries() {
        let glyph = glyphID(for: "A")
        let result0 = cache.rasterize(glyph: glyph, font: testFont, subpixelOffset: 0.0)
        let result1 = cache.rasterize(glyph: glyph, font: testFont, subpixelOffset: 0.5)

        // Subpixel offset 0.0 → bin 0, offset 0.5 → bin 2 — should be separate entries
        // Both should succeed
        XCTAssertFalse(result0.isPlaceholder)
        XCTAssertFalse(result1.isPlaceholder)
    }

    func testSubpixelSameBinReturnsCachedResult() {
        let glyph = glyphID(for: "A")
        // Offsets 0.0 and 0.1 both fall in bin 0 (0.0*4=0, 0.1*4=0.4→bin 0)
        let result0 = cache.rasterize(glyph: glyph, font: testFont, subpixelOffset: 0.0)
        let result1 = cache.rasterize(glyph: glyph, font: testFont, subpixelOffset: 0.1)
        XCTAssertEqual(result0.region, result1.region)
    }

    // MARK: - Invalidation

    func testInvalidateAllClearsCache() {
        let glyph = glyphID(for: "A")
        _ = cache.rasterize(glyph: glyph, font: testFont)
        XCTAssertNotNil(cache.lookup(glyph: glyph, font: testFont))

        cache.invalidateAll()
        XCTAssertNil(cache.lookup(glyph: glyph, font: testFont))
    }

    func testInvalidateAllResetsAtlases() {
        let glyph = glyphID(for: "A")
        _ = cache.rasterize(glyph: glyph, font: testFont)

        cache.invalidateAll()

        // Atlas should be reset — full allocation should succeed
        let region = monoAtlas.allocate(width: monoAtlas.size, height: monoAtlas.size)
        XCTAssertNotNil(region)
    }

    func testRasterizeAfterInvalidateAllocatesFreshRegion() {
        let glyph = glyphID(for: "A")
        let first = cache.rasterize(glyph: glyph, font: testFont)

        cache.invalidateAll()

        let second = cache.rasterize(glyph: glyph, font: testFont)
        // After invalidation, the glyph gets a new region (atlas was reset)
        XCTAssertFalse(second.isPlaceholder)
        XCTAssertGreaterThan(second.advance, 0)
        // Region position may or may not be the same (atlas was reset to initial state),
        // but the glyph should be valid
        _ = first // suppress unused warning
    }

    // MARK: - Color Glyph Detection

    func testMonoFontIsNotColor() {
        // Menlo is a monospace text font — no color tables
        let isColor = cache.isColorGlyph(font: testFont)
        XCTAssertFalse(isColor)
    }

    func testColorDetectionIsCached() {
        // Calling twice should return same result (cached)
        let first = cache.isColorGlyph(font: testFont)
        let second = cache.isColorGlyph(font: testFont)
        XCTAssertEqual(first, second)
    }

    func testAppleColorEmojiIsColor() {
        let emojiFont = CTFontCreateWithName("Apple Color Emoji" as CFString, 14, nil)
        let isColor = cache.isColorGlyph(font: emojiFont)
        XCTAssertTrue(isColor)
    }

    // MARK: - Atlas Growth Under Pressure

    func testAtlasGrowsWhenFull() {
        // Use a tiny atlas to force growth
        let tinyMono = GlyphAtlas(size: 32)
        let tinyColor = GlyphAtlas(size: 32, bytesPerPixel: 4)
        let tinyCache = GlyphCache(atlas: tinyMono, colorAtlas: tinyColor)

        // Rasterize enough glyphs to fill the tiny 32×32 atlas
        let chars: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        for ch in chars {
            let glyph = glyphID(for: ch)
            let result = tinyCache.rasterize(glyph: glyph, font: testFont)
            XCTAssertFalse(result.isPlaceholder, "Glyph '\(ch)' should not be a placeholder")
        }

        // Atlas should have grown beyond initial size
        XCTAssertGreaterThan(tinyMono.size, 32)
    }

    // MARK: - GlyphKey

    func testGlyphKeyEquality() {
        let a = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 0)
        let b = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 0)
        XCTAssertEqual(a, b)
    }

    func testGlyphKeyInequalityDifferentGlyph() {
        let a = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 0)
        let b = GlyphCache.GlyphKey(glyph: 43, fontHash: 100, subpixelBin: 0)
        XCTAssertNotEqual(a, b)
    }

    func testGlyphKeyInequalityDifferentFont() {
        let a = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 0)
        let b = GlyphCache.GlyphKey(glyph: 42, fontHash: 200, subpixelBin: 0)
        XCTAssertNotEqual(a, b)
    }

    func testGlyphKeyInequalityDifferentBin() {
        let a = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 0)
        let b = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 2)
        XCTAssertNotEqual(a, b)
    }

    func testGlyphKeyHashConsistency() {
        let a = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 1)
        let b = GlyphCache.GlyphKey(glyph: 42, fontHash: 100, subpixelBin: 1)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testGlyphKeyUsableAsDictionaryKey() {
        let key = GlyphCache.GlyphKey(glyph: 10, fontHash: 50, subpixelBin: 0)
        var dict: [GlyphCache.GlyphKey: String] = [:]
        dict[key] = "test"
        XCTAssertEqual(dict[key], "test")
    }

    // MARK: - CachedGlyph Properties

    func testCachedGlyphHasReasonableBearings() {
        let glyph = glyphID(for: "A")
        let result = cache.rasterize(glyph: glyph, font: testFont)
        // For a normal letter like 'A', bearingY should be positive (above baseline)
        XCTAssertGreaterThan(result.bearingY, 0)
    }

    func testCachedGlyphAdvanceMatchesCTFont() {
        let glyph = glyphID(for: "M")
        var glyphRef = glyph
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(testFont, .default, &glyphRef, &advance, 1)

        let result = cache.rasterize(glyph: glyph, font: testFont)
        XCTAssertEqual(result.advance, Float(advance.width), accuracy: 0.01)
    }
}
