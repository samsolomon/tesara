import XCTest
@testable import Tesara

final class SyntaxColorMapTests: XCTestCase {

    private func makeTheme() -> TerminalTheme {
        TerminalTheme(
            id: "test", name: "Test",
            foreground: "#cccccc", background: "#1e1e1e",
            cursor: "#cccccc", cursorText: "#000000",
            selectionBackground: "#3c5a96", selectionForeground: nil,
            black: "#000000", red: "#ff0000", green: "#00ff00",
            yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
            cyan: "#00ffff", white: "#ffffff",
            brightBlack: "#808080", brightRed: "#ff5555", brightGreen: "#55ff55",
            brightYellow: "#ffff55", brightBlue: "#5555ff", brightMagenta: "#ff55ff",
            brightCyan: "#55ffff", brightWhite: "#ffffff"
        )
    }

    // MARK: - hexToColorU8

    func testHexWithHash() {
        let c = hexToColorU8("#ff00ff")
        XCTAssertEqual(c.x, 255); XCTAssertEqual(c.y, 0)
        XCTAssertEqual(c.z, 255); XCTAssertEqual(c.w, 255)
    }

    func testHexWithoutHash() {
        let c = hexToColorU8("00ff00")
        XCTAssertEqual(c.x, 0); XCTAssertEqual(c.y, 255); XCTAssertEqual(c.z, 0)
    }

    func testHexCustomAlpha() {
        let c = hexToColorU8("#ff0000", alpha: 128)
        XCTAssertEqual(c.x, 255); XCTAssertEqual(c.w, 128)
    }

    func testHexInvalidReturnsFallback() {
        let c = hexToColorU8("nothex")
        XCTAssertEqual(c.x, 204); XCTAssertEqual(c.y, 204)
        XCTAssertEqual(c.z, 204); XCTAssertEqual(c.w, 255)
    }

    func testHexTooShort() {
        let c = hexToColorU8("#fff")
        XCTAssertEqual(c.x, 204, "Short hex should fall back")
    }

    func testHexBlack() {
        let c = hexToColorU8("#000000")
        XCTAssertEqual(c.x, 0); XCTAssertEqual(c.y, 0); XCTAssertEqual(c.z, 0)
    }

    func testHexWhite() {
        let c = hexToColorU8("#ffffff")
        XCTAssertEqual(c.x, 255); XCTAssertEqual(c.y, 255); XCTAssertEqual(c.z, 255)
    }

    // MARK: - SyntaxColorMap Init

    func testInitMapsFromTheme() {
        let map = SyntaxColorMap(theme: makeTheme())
        XCTAssertEqual(map.keyword, SIMD4<UInt8>(0, 0, 255, 255))   // blue
        XCTAssertEqual(map.string, SIMD4<UInt8>(0, 255, 0, 255))    // green
        XCTAssertEqual(map.comment, SIMD4<UInt8>(128, 128, 128, 255)) // brightBlack
        XCTAssertEqual(map.number, SIMD4<UInt8>(255, 0, 255, 255))  // magenta
        XCTAssertEqual(map.type, SIMD4<UInt8>(255, 255, 0, 255))    // yellow
        XCTAssertEqual(map.operator, SIMD4<UInt8>(255, 0, 0, 255))  // red
        XCTAssertEqual(map.literal, SIMD4<UInt8>(0, 255, 255, 255)) // cyan
        XCTAssertEqual(map.plain, SIMD4<UInt8>(204, 204, 204, 255)) // foreground
    }

    // MARK: - color(for:)

    func testColorForEachKind() {
        let map = SyntaxColorMap(theme: makeTheme())
        XCTAssertEqual(map.color(for: .keyword), map.keyword)
        XCTAssertEqual(map.color(for: .string), map.string)
        XCTAssertEqual(map.color(for: .comment), map.comment)
        XCTAssertEqual(map.color(for: .number), map.number)
        XCTAssertEqual(map.color(for: .type), map.type)
        XCTAssertEqual(map.color(for: .operator), map.operator)
        XCTAssertEqual(map.color(for: .literal), map.literal)
        XCTAssertEqual(map.color(for: .plain), map.plain)
    }

    func testAllKindsHaveNonZeroAlpha() {
        let map = SyntaxColorMap(theme: makeTheme())
        let kinds: [TokenKind] = [.keyword, .string, .comment, .number, .type, .operator, .literal, .plain]
        for kind in kinds {
            XCTAssertEqual(map.color(for: kind).w, 255, "\(kind) should have alpha 255")
        }
    }

    func testDistinctKindsHaveDistinctColors() {
        let map = SyntaxColorMap(theme: makeTheme())
        XCTAssertNotEqual(map.color(for: .keyword), map.color(for: .string))
        XCTAssertNotEqual(map.color(for: .comment), map.color(for: .literal))
        XCTAssertNotEqual(map.color(for: .number), map.color(for: .operator))
    }
}
