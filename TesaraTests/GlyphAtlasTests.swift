import XCTest
@testable import Tesara

final class GlyphAtlasTests: XCTestCase {

    // MARK: - Allocation

    func testAllocateReturnsRegion() {
        let atlas = GlyphAtlas(size: 64)
        let region = atlas.allocate(width: 10, height: 10)
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.width, 10)
        XCTAssertEqual(region?.height, 10)
    }

    func testAllocateMultipleNonOverlapping() {
        let atlas = GlyphAtlas(size: 64)
        let r1 = atlas.allocate(width: 30, height: 30)
        let r2 = atlas.allocate(width: 30, height: 30)
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)

        // Regions should not overlap
        if let r1, let r2 {
            let r1Right = Int(r1.x) + Int(r1.width)
            let r2Right = Int(r2.x) + Int(r2.width)
            let r1Bottom = Int(r1.y) + Int(r1.height)
            let r2Bottom = Int(r2.y) + Int(r2.height)

            let overlapX = r1Right > Int(r2.x) && r2Right > Int(r1.x)
            let overlapY = r1Bottom > Int(r2.y) && r2Bottom > Int(r1.y)
            XCTAssertFalse(overlapX && overlapY, "Regions overlap")
        }
    }

    func testAllocateReturnsNilWhenFull() {
        let atlas = GlyphAtlas(size: 16)
        // Fill the entire atlas
        let r1 = atlas.allocate(width: 16, height: 16)
        XCTAssertNotNil(r1)
        let r2 = atlas.allocate(width: 1, height: 1)
        XCTAssertNil(r2)
    }

    func testAllocateZeroSizeReturnsNil() {
        let atlas = GlyphAtlas(size: 64)
        XCTAssertNil(atlas.allocate(width: 0, height: 10))
        XCTAssertNil(atlas.allocate(width: 10, height: 0))
    }

    // MARK: - Write

    func testWriteData() {
        let atlas = GlyphAtlas(size: 16)
        let region = atlas.allocate(width: 2, height: 2)!
        let data: [UInt8] = [255, 128, 64, 32]
        let prevModified = atlas.modifiedCount
        atlas.write(data: data, to: region)
        XCTAssertGreaterThan(atlas.modifiedCount, prevModified)

        // Verify pixel data
        let x = Int(region.x)
        let y = Int(region.y)
        XCTAssertEqual(atlas.textureData[y * 16 + x], 255)
        XCTAssertEqual(atlas.textureData[y * 16 + x + 1], 128)
        XCTAssertEqual(atlas.textureData[(y + 1) * 16 + x], 64)
        XCTAssertEqual(atlas.textureData[(y + 1) * 16 + x + 1], 32)
    }

    // MARK: - Growth

    func testGrowDoublesSize() {
        let atlas = GlyphAtlas(size: 32)
        XCTAssertTrue(atlas.grow())
        XCTAssertEqual(atlas.size, 64)
    }

    func testGrowPreservesExistingData() {
        let atlas = GlyphAtlas(size: 16)
        let region = atlas.allocate(width: 2, height: 1)!
        let data: [UInt8] = [42, 99]
        atlas.write(data: data, to: region)

        atlas.grow()

        let x = Int(region.x)
        let y = Int(region.y)
        XCTAssertEqual(atlas.textureData[y * atlas.size + x], 42)
        XCTAssertEqual(atlas.textureData[y * atlas.size + x + 1], 99)
    }

    func testGrowAllowsFurtherAllocation() {
        let atlas = GlyphAtlas(size: 16)
        _ = atlas.allocate(width: 16, height: 16) // Fill it
        XCTAssertNil(atlas.allocate(width: 1, height: 1))

        atlas.grow()
        let region = atlas.allocate(width: 1, height: 1)
        XCTAssertNotNil(region)
    }

    func testGrowFailsBeyondMax() {
        let atlas = GlyphAtlas(size: 8192)
        XCTAssertFalse(atlas.grow())
        XCTAssertEqual(atlas.size, 8192)
    }

    // MARK: - Reset

    func testResetClearsAllocations() {
        let atlas = GlyphAtlas(size: 16)
        _ = atlas.allocate(width: 16, height: 16)
        atlas.reset()
        // Should be able to allocate again
        let region = atlas.allocate(width: 16, height: 16)
        XCTAssertNotNil(region)
    }

    // MARK: - Modified Counter

    func testModifiedCountIncrementsOnWrite() {
        let atlas = GlyphAtlas(size: 16)
        let initial = atlas.modifiedCount
        let region = atlas.allocate(width: 1, height: 1)!
        atlas.write(data: [128], to: region)
        XCTAssertEqual(atlas.modifiedCount, initial + 1)
    }

    func testModifiedCountIncrementsOnGrow() {
        let atlas = GlyphAtlas(size: 16)
        let initial = atlas.modifiedCount
        atlas.grow()
        XCTAssertGreaterThan(atlas.modifiedCount, initial)
    }
}
