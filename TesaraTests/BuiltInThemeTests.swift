import XCTest
@testable import Tesara

final class BuiltInThemeTests: XCTestCase {

    // MARK: - CaseIterable

    func testAllCasesCount() {
        XCTAssertEqual(BuiltInTheme.allCases.count, 4)
    }

    func testAllCasesArePresent() {
        let cases = Set(BuiltInTheme.allCases)
        XCTAssertTrue(cases.contains(.tesaraDark))
        XCTAssertTrue(cases.contains(.tesaraLight))
        XCTAssertTrue(cases.contains(.paperDark))
        XCTAssertTrue(cases.contains(.paperLight))
    }

    // MARK: - ID

    func testIDMatchesRawValue() {
        for theme in BuiltInTheme.allCases {
            XCTAssertEqual(theme.id, theme.rawValue)
        }
    }

    func testIDMatchesThemeID() {
        for builtIn in BuiltInTheme.allCases {
            XCTAssertEqual(builtIn.id, builtIn.theme.id)
        }
    }

    // MARK: - Theme Names

    func testThemeNames() {
        XCTAssertEqual(BuiltInTheme.tesaraDark.theme.name, "Tesara Dark")
        XCTAssertEqual(BuiltInTheme.tesaraLight.theme.name, "Tesara Light")
        XCTAssertEqual(BuiltInTheme.paperDark.theme.name, "Paper Dark")
        XCTAssertEqual(BuiltInTheme.paperLight.theme.name, "Paper Light")
    }

    // MARK: - Required Colors

    func testAllThemesHaveNonEmptyColors() {
        for builtIn in BuiltInTheme.allCases {
            let t = builtIn.theme
            XCTAssertFalse(t.foreground.isEmpty, "\(builtIn) missing foreground")
            XCTAssertFalse(t.background.isEmpty, "\(builtIn) missing background")
            XCTAssertFalse(t.cursor.isEmpty, "\(builtIn) missing cursor")
            XCTAssertFalse(t.cursorText.isEmpty, "\(builtIn) missing cursorText")
            XCTAssertFalse(t.selectionBackground.isEmpty, "\(builtIn) missing selectionBackground")
            XCTAssertFalse(t.black.isEmpty, "\(builtIn) missing black")
            XCTAssertFalse(t.red.isEmpty, "\(builtIn) missing red")
            XCTAssertFalse(t.green.isEmpty, "\(builtIn) missing green")
            XCTAssertFalse(t.yellow.isEmpty, "\(builtIn) missing yellow")
            XCTAssertFalse(t.blue.isEmpty, "\(builtIn) missing blue")
            XCTAssertFalse(t.magenta.isEmpty, "\(builtIn) missing magenta")
            XCTAssertFalse(t.cyan.isEmpty, "\(builtIn) missing cyan")
            XCTAssertFalse(t.white.isEmpty, "\(builtIn) missing white")
            XCTAssertFalse(t.brightBlack.isEmpty, "\(builtIn) missing brightBlack")
            XCTAssertFalse(t.brightRed.isEmpty, "\(builtIn) missing brightRed")
            XCTAssertFalse(t.brightGreen.isEmpty, "\(builtIn) missing brightGreen")
            XCTAssertFalse(t.brightYellow.isEmpty, "\(builtIn) missing brightYellow")
            XCTAssertFalse(t.brightBlue.isEmpty, "\(builtIn) missing brightBlue")
            XCTAssertFalse(t.brightMagenta.isEmpty, "\(builtIn) missing brightMagenta")
            XCTAssertFalse(t.brightCyan.isEmpty, "\(builtIn) missing brightCyan")
            XCTAssertFalse(t.brightWhite.isEmpty, "\(builtIn) missing brightWhite")
        }
    }

    func testAllThemesHaveValidHexColors() {
        for builtIn in BuiltInTheme.allCases {
            let t = builtIn.theme
            let colors = [
                t.foreground, t.background, t.cursor, t.cursorText, t.selectionBackground,
                t.black, t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan, t.white,
                t.brightBlack, t.brightRed, t.brightGreen, t.brightYellow,
                t.brightBlue, t.brightMagenta, t.brightCyan, t.brightWhite,
            ]
            for color in colors {
                XCTAssertTrue(color.hasPrefix("#"), "\(builtIn): color '\(color)' missing # prefix")
                let hex = String(color.dropFirst())
                XCTAssertEqual(hex.count, 6, "\(builtIn): color '\(color)' is not 6-char hex")
                XCTAssertNotNil(UInt64(hex, radix: 16), "\(builtIn): color '\(color)' is not valid hex")
            }
        }
    }

    func testAllThemesHaveSelectionForeground() {
        for builtIn in BuiltInTheme.allCases {
            XCTAssertNotNil(builtIn.theme.selectionForeground, "\(builtIn) missing selectionForeground")
        }
    }

    // MARK: - Dark vs Light

    func testDarkThemesHaveDarkBackgrounds() {
        XCTAssertTrue(BuiltInTheme.tesaraDark.theme.isDarkBackground)
        XCTAssertTrue(BuiltInTheme.paperDark.theme.isDarkBackground)
    }

    func testLightThemesHaveLightBackgrounds() {
        XCTAssertFalse(BuiltInTheme.tesaraLight.theme.isDarkBackground)
        XCTAssertFalse(BuiltInTheme.paperLight.theme.isDarkBackground)
    }

    // MARK: - Link Color

    func testAllThemesHaveLinkColor() {
        for builtIn in BuiltInTheme.allCases {
            XCTAssertNotNil(builtIn.theme.linkColor, "\(builtIn) missing linkColor")
        }
    }

    // MARK: - Codable Round Trip

    func testThemeCodableRoundTrip() throws {
        for builtIn in BuiltInTheme.allCases {
            let original = builtIn.theme
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(TerminalTheme.self, from: data)
            XCTAssertEqual(decoded, original, "\(builtIn) failed Codable round trip")
        }
    }
}
