import XCTest
@testable import Tesara

@MainActor
final class EditorLayoutEngineTests: XCTestCase {

    private func makeEngine() -> EditorLayoutEngine {
        EditorLayoutEngine(fontFamily: "Menlo", fontSize: 13)
    }

    private func makeStorage(lines: [String]) -> TextStorage {
        let storage = TextStorage()
        storage.loadString(lines.joined(separator: "\n"))
        return storage
    }

    // MARK: - Init & Font

    func testInitSetsPositiveLineHeight() {
        let engine = makeEngine()
        XCTAssertGreaterThan(engine.lineHeight, 0)
    }

    func testUpdateFontChangesLineHeight() {
        let engine = makeEngine()
        let originalHeight = engine.lineHeight
        engine.updateFont(family: "Menlo", size: 26)
        XCTAssertGreaterThan(engine.lineHeight, originalHeight)
    }

    func testUpdateFontUpdatesFont() {
        let engine = makeEngine()
        engine.updateFont(family: "Courier", size: 18)
        let name = CTFontCopyPostScriptName(engine.font) as String
        XCTAssertTrue(name.lowercased().contains("courier"))
    }

    // MARK: - layoutVisibleLines (no wrap)

    func testLayoutNoWrapReturnsSingleVisualLinePerStorageLine() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["hello", "world", "test"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        XCTAssertEqual(lines.count, 3)
        for (i, line) in lines.enumerated() {
            XCTAssertEqual(line.lineIndex, i)
            XCTAssertEqual(line.wrapIndex, 0)
            XCTAssertEqual(line.stringOffset, 0)
        }
    }

    func testLayoutNoWrapRespectsScrollOffset() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["line0", "line1", "line2", "line3", "line4"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 2,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        XCTAssertEqual(lines.first?.lineIndex, 2)
    }

    func testLayoutNoWrapClampsToStorageLineCount() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["only one line"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 10000, scale: 1.0, wordWrap: false
        )
        XCTAssertEqual(lines.count, 1)
    }

    func testLayoutNoWrapLinesHaveIncreasingYOrigins() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["aaa", "bbb", "ccc"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        for i in 1..<lines.count {
            XCTAssertGreaterThan(lines[i].origin.y, lines[i - 1].origin.y)
        }
    }

    // MARK: - layoutVisibleLines (word wrap)

    func testLayoutWordWrapProducesMultipleVisualLinesForLongLine() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: [longLine])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 200, viewportHeight: 2000, scale: 1.0, wordWrap: true
        )
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines { XCTAssertEqual(line.lineIndex, 0) }
        for (i, line) in lines.enumerated() { XCTAssertEqual(line.wrapIndex, i) }
    }

    func testLayoutWordWrapStringOffsetsIncrease() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: [longLine])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 200, viewportHeight: 2000, scale: 1.0, wordWrap: true
        )
        for i in 1..<lines.count {
            XCTAssertGreaterThan(lines[i].stringOffset, lines[i - 1].stringOffset)
        }
    }

    func testLayoutWordWrapMixedLines() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: ["short", longLine, "end"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 200, viewportHeight: 5000, scale: 1.0, wordWrap: true
        )
        XCTAssertEqual(lines.first?.lineIndex, 0)
        XCTAssertEqual(lines.last?.lineIndex, 2)
    }

    func testLayoutWordWrapScrollIntoWrappedLine() {
        let engine = makeEngine()
        let longLine = String(repeating: "abcdefghij ", count: 50)
        let storage = makeStorage(lines: [longLine, "end"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        let wraps = engine.visualLineMap.wrapCounts[0]
        guard wraps > 2 else { return }
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 1,
            viewportWidth: 200, viewportHeight: 2000, scale: 1.0, wordWrap: true
        )
        XCTAssertEqual(lines.first?.lineIndex, 0)
        XCTAssertEqual(lines.first?.wrapIndex, 1)
        XCTAssertGreaterThan(lines.first?.stringOffset ?? 0, 0)
    }

    func testLayoutEmptyStorage() {
        let engine = makeEngine()
        let storage = makeStorage(lines: [""])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: true
        )
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].lineIndex, 0)
    }

    // MARK: - Hit Testing

    func testHitTestFirstLine() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["hello world"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        let pos = engine.hitTest(point: CGPoint(x: 0, y: 0), in: lines, scale: 1.0)
        XCTAssertEqual(pos.line, 0)
        XCTAssertEqual(pos.column, 0)
    }

    func testHitTestSecondLine() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["hello", "world"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        let y = lines[1].origin.y + 1
        let pos = engine.hitTest(point: CGPoint(x: 0, y: y), in: lines, scale: 1.0)
        XCTAssertEqual(pos.line, 1)
    }

    func testHitTestBelowAllLines() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["hello"])
        let lines = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        let pos = engine.hitTest(point: CGPoint(x: 0, y: 9999), in: lines, scale: 1.0)
        XCTAssertEqual(pos.line, 0)
    }

    func testHitTestEmptyLayoutReturnsOrigin() {
        let engine = makeEngine()
        let pos = engine.hitTest(point: CGPoint(x: 50, y: 50), in: [], scale: 1.0)
        XCTAssertEqual(pos, TextStorage.Position(line: 0, column: 0))
    }

    func testHitTestWithScaleFactor() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["hello world testing"])
        let lines1x = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        let lines2x = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 2.0, wordWrap: false
        )
        let pos1 = engine.hitTest(point: CGPoint(x: 50, y: 0), in: lines1x, scale: 1.0)
        let pos2 = engine.hitTest(point: CGPoint(x: 100, y: 0), in: lines2x, scale: 2.0)
        XCTAssertEqual(pos1.column, pos2.column)
    }

    // MARK: - Scale

    func testLayoutLinesScaleAffectsOrigin() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["aaa", "bbb"])
        let lines1x = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 400, scale: 1.0, wordWrap: false
        )
        let lines2x = engine.layoutVisibleLines(
            storage: storage, scrollVisualLine: 0,
            viewportWidth: 800, viewportHeight: 800, scale: 2.0, wordWrap: false
        )
        XCTAssertEqual(lines2x[1].origin.y, lines1x[1].origin.y * 2, accuracy: 1.0)
    }

    // MARK: - VisualLineMap via recomputeWrapCounts

    func testRecomputeWithSameContentIsStable() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["short", "also short", "tiny"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        let originalTotal = engine.visualLineMap.totalVisualLines
        let originalSums = engine.visualLineMap.prefixSums
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, originalTotal)
        XCTAssertEqual(engine.visualLineMap.prefixSums, originalSums)
    }

    func testRecomputeWithEditedContentUpdates() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["short", "also short", "tiny"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 200)
        XCTAssertEqual(engine.visualLineMap.wrapCounts[1], 1)
        let longContent = String(repeating: "abcdefghij ", count: 50)
        let newStorage = makeStorage(lines: ["short", longContent, "tiny"])
        engine.recomputeWrapCounts(storage: newStorage, viewportWidth: 200)
        XCTAssertGreaterThan(engine.visualLineMap.wrapCounts[1], 1)
    }

    func testRecomputeWithInsertedLine() {
        let engine = makeEngine()
        let storage = makeStorage(lines: ["aaa", "bbb"])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 2)
        let newStorage = makeStorage(lines: ["aaa", "new", "bbb"])
        engine.recomputeWrapCounts(storage: newStorage, viewportWidth: 800)
        XCTAssertEqual(engine.visualLineMap.wrapCounts.count, 3)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 3)
    }

    func testRecomputeEmptyStorage() {
        let engine = makeEngine()
        let storage = makeStorage(lines: [""])
        engine.recomputeWrapCounts(storage: storage, viewportWidth: 800)
        XCTAssertEqual(engine.visualLineMap.totalVisualLines, 1)
        XCTAssertEqual(engine.visualLineMap.wrapCounts, [1])
    }
}
