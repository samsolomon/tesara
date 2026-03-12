import XCTest
@testable import Tesara

final class TranscriptLogTests: XCTestCase {
    func testEmptyInitialState() {
        let log = TranscriptLog()
        XCTAssertEqual(log.totalLength, 0)
        XCTAssertTrue(log.segments.isEmpty)
    }

    func testAppendIncreasesTotalLength() {
        var log = TranscriptLog()
        log.append("hello")
        XCTAssertEqual(log.totalLength, 5)
        XCTAssertEqual(log.segments.count, 1)
    }

    func testAppendMultipleSegments() {
        var log = TranscriptLog()
        log.append("hello ")
        log.append("world")
        XCTAssertEqual(log.totalLength, 11)
        XCTAssertEqual(log.segments.count, 2)
        XCTAssertEqual(log.segments[0].offset, 0)
        XCTAssertEqual(log.segments[1].offset, 6)
    }

    func testAppendEmptyStringIsIgnored() {
        var log = TranscriptLog()
        log.append("")
        XCTAssertEqual(log.totalLength, 0)
        XCTAssertTrue(log.segments.isEmpty)
    }

    func testContentSinceOffsetZero() {
        var log = TranscriptLog()
        log.append("hello ")
        log.append("world")
        XCTAssertEqual(log.contentSince(offset: 0), "hello world")
    }

    func testContentSinceMiddleOffset() {
        var log = TranscriptLog()
        log.append("hello ")
        log.append("world")
        XCTAssertEqual(log.contentSince(offset: 6), "world")
    }

    func testContentSinceMidSegment() {
        var log = TranscriptLog()
        log.append("hello world")
        XCTAssertEqual(log.contentSince(offset: 6), "world")
    }

    func testContentSinceAtEnd() {
        var log = TranscriptLog()
        log.append("hello")
        XCTAssertEqual(log.contentSince(offset: 5), "")
    }

    func testContentSinceBeyondEnd() {
        var log = TranscriptLog()
        log.append("hello")
        XCTAssertEqual(log.contentSince(offset: 100), "")
    }

    func testReset() {
        var log = TranscriptLog()
        log.append("hello")
        log.append("world")
        log.reset()
        XCTAssertEqual(log.totalLength, 0)
        XCTAssertTrue(log.segments.isEmpty)
    }

    func testResetThenAppend() {
        var log = TranscriptLog()
        log.append("first")
        log.reset()
        log.append("second")
        XCTAssertEqual(log.totalLength, 6)
        XCTAssertEqual(log.contentSince(offset: 0), "second")
    }

    func testMultibyteUTF8() {
        var log = TranscriptLog()
        log.append("café")
        // "café" is 5 UTF-8 bytes (c=1, a=1, f=1, é=2)
        XCTAssertEqual(log.totalLength, 5)
    }

    func testIncrementalAppendPattern() {
        var log = TranscriptLog()
        var offset = 0

        log.append("line 1\n")
        let chunk1 = log.contentSince(offset: offset)
        XCTAssertEqual(chunk1, "line 1\n")
        offset = log.totalLength

        log.append("line 2\n")
        let chunk2 = log.contentSince(offset: offset)
        XCTAssertEqual(chunk2, "line 2\n")
        offset = log.totalLength

        // Full content still available
        XCTAssertEqual(log.contentSince(offset: 0), "line 1\nline 2\n")
    }
}
