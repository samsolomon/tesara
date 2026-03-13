import XCTest
@testable import Tesara

@MainActor
final class VisualLineMapTests: XCTestCase {

    private func makeEngine() -> EditorLayoutEngine {
        EditorLayoutEngine(fontFamily: "Menlo", fontSize: 13)
    }

    private func makeStorage(lines: [String]) -> TextStorage {
        let storage = TextStorage()
        let content = lines.joined(separator: "\n")
        storage.loadString(content)
        return storage
    }

    // MARK: - Basic Mapping

    func testNoWrapSingleVisualLinePerStorageLine() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["short", "also short", "tiny"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 3)
        XCTAssertEqual(engine.visualLineMap.wrapCounts, [1, 1, 1])
    }

    func testLongLineProducesMultipleVisualLines() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50) // ~550 chars
        let storage = makeStorage(lines: [longLine, "short"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)

        XCTAssertGreaterThan(engine.visualLineMap.wrapCounts[0], 1, "Long line should wrap")
        XCTAssertEqual(engine.visualLineMap.wrapCounts[1], 1, "Short line should not wrap")
        XCTAssertEqual(engine.visualLineMap.totalVisualLines,
                       engine.visualLineMap.wrapCounts[0] + 1)
    }

    func testEmptyLineCountsAsOne() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["", "hello", ""])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        XCTAssertEqual(engine.visualLineMap.wrapCounts, [1, 1, 1])
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 3)
    }

    // MARK: - storagePosition ↔ visualLine

    func testStoragePositionRoundTrip() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["aaa", "bbb", "ccc", "ddd"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        for i in 0..<4 {
            let visualLine = engine.visualLineMap.visualLine(fromStorageLine: i)
            let (storageLine, wrapIndex) = engine.visualLineMap.storagePosition(fromVisualLine: visualLine)
            XCTAssertEqual(storageLine, i)
            XCTAssertEqual(wrapIndex, 0)
        }
    }

    func testStoragePositionWithWrapping() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: [longLine, "short"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)

        let wraps = engine.visualLineMap.wrapCounts[0]

        // Visual line 0 → storage line 0, wrap 0
        let (s0, w0) = engine.visualLineMap.storagePosition(fromVisualLine: 0)
        XCTAssertEqual(s0, 0)
        XCTAssertEqual(w0, 0)

        // Visual line (wraps - 1) → storage line 0, last wrap
        let (s1, w1) = engine.visualLineMap.storagePosition(fromVisualLine: wraps - 1)
        XCTAssertEqual(s1, 0)
        XCTAssertEqual(w1, wraps - 1)

        // Visual line (wraps) → storage line 1, wrap 0
        let (s2, w2) = engine.visualLineMap.storagePosition(fromVisualLine: wraps)
        XCTAssertEqual(s2, 1)
        XCTAssertEqual(w2, 0)
    }

    func testVisualLineFromStorageLine() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: ["short", longLine, "end"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)

        // First line starts at visual 0
        XCTAssertEqual(engine.visualLineMap.visualLine(fromStorageLine: 0), 0)

        // Second line starts at visual 1 (after the first line's 1 visual line)
        XCTAssertEqual(engine.visualLineMap.visualLine(fromStorageLine: 1), 1)

        // Third line starts after all visual lines from line 0 + line 1
        let expectedVisualStart = 1 + engine.visualLineMap.wrapCounts[1]
        XCTAssertEqual(engine.visualLineMap.visualLine(fromStorageLine: 2), expectedVisualStart)
    }

    // MARK: - Prefix Sums

    func testPrefixSumsAreCorrect() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["aaa", "bbb", "ccc"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        // For non-wrapping: prefix sums should be [0, 1, 2, 3]
        XCTAssertEqual(engine.visualLineMap.prefixSums, [0, 1, 2, 3])
    }

    // MARK: - Recompute After Edit

    func testRecomputeAfterEditUpdatesCorrectly() {
        let engine = makeEngine()

        // Start with short lines
        let storage1 = makeStorage(lines: ["short", "also short", "tiny"])
        engine.recomputeWrapCounts(storage: storage1, viewportWidth: 200)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 3)

        // Replace line 1 with a very long line and recompute
        let longContent = String(repeating: "abcdefghij ", count: 50)
        let storage2 = makeStorage(lines: ["short", longContent, "tiny"])
        engine.recomputeWrapCounts(storage: storage2, viewportWidth: 200)

        XCTAssertGreaterThan(engine.visualLineMap.wrapCounts[1], 1)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines,
                       1 + engine.visualLineMap.wrapCounts[1] + 1)
    }

    func testRecomputeWithSameContentIsStable() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["short", "also short"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        let originalSums = engine.visualLineMap.prefixSums
        let originalTotal = engine.visualLineMap.totalVisualLines

        // Recompute with same storage — should produce identical results
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        XCTAssertEqual(engine.visualLineMap.prefixSums, originalSums)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, originalTotal)
    }

    // MARK: - Edge Cases

    func testOutOfBoundsStorageLineReturnsTotal() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["a", "b"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)

        XCTAssertEqual(engine.visualLineMap.visualLine(fromStorageLine: 5), engine.visualLineMap.totalVisualLines)
        XCTAssertEqual(engine.visualLineMap.visualLine(fromStorageLine: -1), engine.visualLineMap.totalVisualLines)
    }

    func testResizeChangesWrapCounts() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: [longLine])

        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        let wrapsWide = engine.visualLineMap.wrapCounts[0]

        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        let wrapsNarrow = engine.visualLineMap.wrapCounts[0]

        XCTAssertGreaterThan(wrapsNarrow, wrapsWide, "Narrower viewport should produce more wraps")
    }
}
