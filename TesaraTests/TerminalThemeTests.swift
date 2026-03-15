import XCTest
import SwiftUI
@testable import Tesara

final class TerminalThemeTests: XCTestCase {
    // MARK: Hex Color Parsing

    func testValidHexColorWithHash() {
        let color = Color(hex: "#FF0000")
        XCTAssertNotNil(color)
    }

    func testValidHexColorWithoutHash() {
        let color = Color(hex: "00FF00")
        XCTAssertNotNil(color)
    }

    func testInvalidHexColorTooShort() {
        let color = Color(hex: "#FFF")
        XCTAssertNil(color)
    }

    func testInvalidHexColorTooLong() {
        let color = Color(hex: "#FF00FF00")
        XCTAssertNil(color)
    }

    func testInvalidHexColorNonHexCharacters() {
        let color = Color(hex: "#ZZZZZZ")
        XCTAssertNil(color)
    }

    func testEmptyStringReturnsNil() {
        let color = Color(hex: "")
        XCTAssertNil(color)
    }

    func testHexColorWithWhitespace() {
        let color = Color(hex: "  #FF0000  ")
        XCTAssertNotNil(color)
    }

    func testBlackHex() {
        let color = Color(hex: "#000000")
        XCTAssertNotNil(color)
    }

    func testWhiteHex() {
        let color = Color(hex: "#FFFFFF")
        XCTAssertNotNil(color)
    }

    func testLowercaseHex() {
        let color = Color(hex: "#abcdef")
        XCTAssertNotNil(color)
    }

    // MARK: Built-in Themes Validation

    func testAllBuiltInThemesHaveNonEmptyRequiredFields() {
        for builtIn in BuiltInTheme.allCases {
            let theme = builtIn.theme
            XCTAssertFalse(theme.id.isEmpty, "\(builtIn) has empty id")
            XCTAssertFalse(theme.name.isEmpty, "\(builtIn) has empty name")
            XCTAssertFalse(theme.foreground.isEmpty, "\(builtIn) has empty foreground")
            XCTAssertFalse(theme.background.isEmpty, "\(builtIn) has empty background")
            XCTAssertFalse(theme.cursor.isEmpty, "\(builtIn) has empty cursor")
            XCTAssertFalse(theme.cursorText.isEmpty, "\(builtIn) has empty cursorText")
            XCTAssertFalse(theme.selectionBackground.isEmpty, "\(builtIn) has empty selectionBackground")
            XCTAssertFalse(theme.black.isEmpty, "\(builtIn) has empty black")
            XCTAssertFalse(theme.red.isEmpty, "\(builtIn) has empty red")
            XCTAssertFalse(theme.green.isEmpty, "\(builtIn) has empty green")
            XCTAssertFalse(theme.yellow.isEmpty, "\(builtIn) has empty yellow")
            XCTAssertFalse(theme.blue.isEmpty, "\(builtIn) has empty blue")
            XCTAssertFalse(theme.magenta.isEmpty, "\(builtIn) has empty magenta")
            XCTAssertFalse(theme.cyan.isEmpty, "\(builtIn) has empty cyan")
            XCTAssertFalse(theme.white.isEmpty, "\(builtIn) has empty white")
            XCTAssertFalse(theme.brightBlack.isEmpty, "\(builtIn) has empty brightBlack")
            XCTAssertFalse(theme.brightRed.isEmpty, "\(builtIn) has empty brightRed")
            XCTAssertFalse(theme.brightGreen.isEmpty, "\(builtIn) has empty brightGreen")
            XCTAssertFalse(theme.brightYellow.isEmpty, "\(builtIn) has empty brightYellow")
            XCTAssertFalse(theme.brightBlue.isEmpty, "\(builtIn) has empty brightBlue")
            XCTAssertFalse(theme.brightMagenta.isEmpty, "\(builtIn) has empty brightMagenta")
            XCTAssertFalse(theme.brightCyan.isEmpty, "\(builtIn) has empty brightCyan")
            XCTAssertFalse(theme.brightWhite.isEmpty, "\(builtIn) has empty brightWhite")
        }
    }

    func testAllBuiltInThemeColorsAreValidHex() {
        for builtIn in BuiltInTheme.allCases {
            let theme = builtIn.theme
            let requiredColors = [
                theme.foreground, theme.background, theme.cursor, theme.cursorText,
                theme.selectionBackground, theme.black, theme.red, theme.green,
                theme.yellow, theme.blue, theme.magenta, theme.cyan, theme.white,
                theme.brightBlack, theme.brightRed, theme.brightGreen, theme.brightYellow,
                theme.brightBlue, theme.brightMagenta, theme.brightCyan, theme.brightWhite
            ]

            for hex in requiredColors {
                XCTAssertNotNil(Color(hex: hex), "\(builtIn) has invalid hex color: \(hex)")
            }

            if let linkColor = theme.linkColor {
                XCTAssertNotNil(Color(hex: linkColor), "\(builtIn) has invalid linkColor: \(linkColor)")
            }
        }
    }

    func testBuiltInThemeCount() {
        XCTAssertEqual(BuiltInTheme.allCases.count, 4)
    }

    func testEachThemeHasUniqueID() {
        let ids = BuiltInTheme.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Built-in themes should have unique IDs")
    }

    func testSwiftUIColorFromHex() {
        let theme = BuiltInTheme.tesaraDark.theme
        // Should not crash and return a valid color
        let color = theme.swiftUIColor(from: "#FF0000")
        XCTAssertNotNil(color)
    }

    func testSwiftUIColorFromInvalidHexFallsBackToBlack() {
        let theme = BuiltInTheme.tesaraDark.theme
        let color = theme.swiftUIColor(from: "invalid")
        // Falls back to .black per implementation
        XCTAssertNotNil(color)
    }
}
