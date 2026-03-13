import XCTest
@testable import Tesara

/// Performance benchmarks for Tesara's critical data paths.
/// Run via Cmd+U or individually from the Test Navigator.
final class PerformanceBenchmarkTests: XCTestCase {

    // MARK: - UTF-8 Decoding

    /// Measures the cost of String(data:encoding:.utf8) on 4KB chunks.
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
