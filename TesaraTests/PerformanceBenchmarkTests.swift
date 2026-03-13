import XCTest
@testable import Tesara

/// Performance benchmarks for Tesara's critical data paths.
/// Run via Cmd+U or individually from the Test Navigator.
final class PerformanceBenchmarkTests: XCTestCase {

    // MARK: - TranscriptLog Throughput

    /// Measures append throughput: simulates rapid PTY output hitting the log.
    func testTranscriptLogAppendThroughput() {
        let chunk = String(repeating: "x", count: 4096) // Match PTY 4KB buffer size
        var log = TranscriptLog()

        measure {
            for _ in 0..<1000 {
                log.append(chunk) // ~4MB total
            }
        }
    }

    /// Measures contentSince reads under a full buffer (1MB retained).
    func testTranscriptLogReadThroughput() {
        var log = TranscriptLog()
        let chunk = String(repeating: "y", count: 4096)

        // Fill past the 1MB retention limit to trigger pruning
        for _ in 0..<500 {
            log.append(chunk) // ~2MB total, pruned to ~1MB
        }

        let midpoint = log.totalLength / 2

        measure {
            for _ in 0..<100 {
                _ = log.contentSince(offset: midpoint)
            }
        }
    }

    /// Measures pruning cost: appending past the 1MB limit forces segment removal.
    func testTranscriptLogPruningOverhead() {
        var log = TranscriptLog()
        let chunk = String(repeating: "z", count: 4096)

        // Pre-fill to near the limit
        for _ in 0..<256 {
            log.append(chunk) // ~1MB
        }

        measure {
            // Each append now triggers pruning
            for _ in 0..<256 {
                log.append(chunk)
            }
        }
    }

    // MARK: - TranscriptLog Memory

    /// Verifies the 1MB cap holds: append 10MB and check segments don't grow unbounded.
    func testTranscriptLogMemoryCap() {
        var log = TranscriptLog()
        let chunk = String(repeating: "m", count: 4096)

        for _ in 0..<2500 { // ~10MB
            log.append(chunk)
        }

        // Retained bytes should be ≤ 1MB (1_048_576)
        let retained = log.segments.reduce(0) { $0 + $1.text.utf8.count }
        XCTAssertLessThanOrEqual(retained, 1_200_000,
            "TranscriptLog retained \(retained) bytes, expected ≤ ~1MB")
    }

    // MARK: - UTF-8 Decoding (PTY hot path)

    /// Measures the cost of String(data:encoding:.utf8) on 4KB chunks,
    /// which is the inner loop of drainReadableData().
    func testUTF8DecodingThroughput() {
        let asciiData = Data(String(repeating: "A", count: 4096).utf8)

        measure {
            for _ in 0..<10_000 {
                _ = String(data: asciiData, encoding: .utf8)
            }
        }
    }

    /// Same test but with multi-byte UTF-8 (CJK characters).
    func testUTF8DecodingMultibyteThroughput() {
        // CJK chars are 3 bytes each in UTF-8
        let cjk = String(repeating: "\u{4E00}", count: 1365) // ~4KB in UTF-8
        let cjkData = Data(cjk.utf8)

        measure {
            for _ in 0..<10_000 {
                _ = String(data: cjkData, encoding: .utf8)
            }
        }
    }

    // MARK: - OSC133 Parser Throughput

    /// Measures parser performance on interleaved text + escape sequences.
    func testOSC133ParserThroughput() {
        let parser = OSC133Parser()
        // Simulate shell output with prompt markers
        let chunk = "\u{1b}]133;A\u{7}$ echo hello\u{1b}]133;B\u{7}hello\n\u{1b}]133;C\u{7}\u{1b}]133;D;0\u{7}"

        measure {
            for _ in 0..<10_000 {
                _ = parser.feed(chunk)
            }
        }
    }

    /// Measures parser on plain text (no escape sequences) — common case.
    func testOSC133ParserPlainTextThroughput() {
        let parser = OSC133Parser()
        let plain = String(repeating: "output line\n", count: 100) // ~1.2KB

        measure {
            for _ in 0..<10_000 {
                _ = parser.feed(plain)
            }
        }
    }
}
