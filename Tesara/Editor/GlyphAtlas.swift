import Foundation

/// Guillotine bin-packing texture atlas for glyph rasterization.
/// Single-channel (grayscale) — color emoji renders as placeholder boxes.
final class GlyphAtlas {

    struct Region: Equatable {
        var x: UInt16
        var y: UInt16
        var width: UInt16
        var height: UInt16
    }

    private(set) var size: Int
    private(set) var textureData: [UInt8]
    private(set) var modifiedCount: UInt64 = 0

    /// Free rectangles available for allocation (guillotine algorithm).
    private var freeRects: [Region]

    init(size: Int = 512) {
        self.size = size
        self.textureData = [UInt8](repeating: 0, count: size * size)
        self.freeRects = [Region(x: 0, y: 0, width: UInt16(size), height: UInt16(size))]
    }

    /// Allocate a region of the given size. Returns nil if the atlas needs to grow.
    func allocate(width: Int, height: Int) -> Region? {
        guard width > 0, height > 0 else { return nil }
        let w = UInt16(width)
        let h = UInt16(height)

        // Find best-fit free rect (smallest area that fits)
        var bestIndex = -1
        var bestArea = Int.max
        for (i, rect) in freeRects.enumerated() {
            guard rect.width >= w, rect.height >= h else { continue }
            let area = Int(rect.width) * Int(rect.height)
            if area < bestArea {
                bestArea = area
                bestIndex = i
            }
        }

        guard bestIndex >= 0 else { return nil }

        let chosen = freeRects[bestIndex]
        let allocated = Region(x: chosen.x, y: chosen.y, width: w, height: h)

        // Remove chosen rect and split remainder (guillotine)
        freeRects.remove(at: bestIndex)

        let rightWidth = chosen.width - w
        let bottomHeight = chosen.height - h

        // Split along shorter axis for better packing
        if rightWidth > 0 {
            freeRects.append(Region(
                x: chosen.x + w,
                y: chosen.y,
                width: rightWidth,
                height: h
            ))
        }
        if bottomHeight > 0 {
            freeRects.append(Region(
                x: chosen.x,
                y: chosen.y + h,
                width: chosen.width,
                height: bottomHeight
            ))
        }

        return allocated
    }

    /// Write pixel data into the atlas at the given region.
    func write(data: [UInt8], to region: Region) {
        let w = Int(region.width)
        let h = Int(region.height)
        guard data.count >= w * h else { return }

        for row in 0..<h {
            let dstY = Int(region.y) + row
            let dstOffset = dstY * size + Int(region.x)
            let srcOffset = row * w
            textureData.replaceSubrange(dstOffset..<(dstOffset + w), with: data[srcOffset..<(srcOffset + w)])
        }

        modifiedCount += 1
    }

    /// Double the atlas size, copying existing data. Returns true on success.
    @discardableResult
    func grow() -> Bool {
        let oldSize = size
        let newSize = oldSize * 2
        guard newSize <= 8192 else { return false }

        var newData = [UInt8](repeating: 0, count: newSize * newSize)
        for row in 0..<oldSize {
            let srcOffset = row * oldSize
            let dstOffset = row * newSize
            newData.replaceSubrange(dstOffset..<(dstOffset + oldSize), with: textureData[srcOffset..<(srcOffset + oldSize)])
        }

        // Add newly available space as free rects
        // Right strip: full new height, width = old size
        freeRects.append(Region(
            x: UInt16(oldSize),
            y: 0,
            width: UInt16(oldSize),
            height: UInt16(newSize)
        ))
        // Bottom strip: old width, height = old size
        freeRects.append(Region(
            x: 0,
            y: UInt16(oldSize),
            width: UInt16(oldSize),
            height: UInt16(oldSize)
        ))

        self.size = newSize
        self.textureData = newData
        self.modifiedCount += 1
        return true
    }

    /// Clear all allocations and reset.
    func reset() {
        textureData = [UInt8](repeating: 0, count: size * size)
        freeRects = [Region(x: 0, y: 0, width: UInt16(size), height: UInt16(size))]
        modifiedCount += 1
    }
}
