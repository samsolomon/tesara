import XCTest
@testable import Tesara

final class GhosttyThemeLoaderTests: XCTestCase {

    // MARK: - Basic Parsing

    func testParseMinimalTheme() {
        let content = """
        background = #1e1e1e
        foreground = #d4d4d4
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Minimal", id: "test-minimal")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.background, "#1e1e1e")
        XCTAssertEqual(theme?.foreground, "#d4d4d4")
        XCTAssertEqual(theme?.name, "Minimal")
        XCTAssertEqual(theme?.id, "test-minimal")
    }

    func testParseMissingBackgroundReturnsNil() {
        let content = "foreground = #d4d4d4"
        XCTAssertNil(GhosttyThemeLoader.parse(content: content, name: "Bad", id: "bad"))
    }

    func testParseMissingForegroundReturnsNil() {
        let content = "background = #1e1e1e"
        XCTAssertNil(GhosttyThemeLoader.parse(content: content, name: "Bad", id: "bad"))
    }

    func testParseEmptyContentReturnsNil() {
        XCTAssertNil(GhosttyThemeLoader.parse(content: "", name: "Empty", id: "empty"))
    }

    // MARK: - Comments and Blank Lines

    func testParseSkipsComments() {
        let content = """
        # This is a comment
        background = #000000
        # Another comment
        foreground = #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Comments", id: "comments")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.background, "#000000")
        XCTAssertEqual(theme?.foreground, "#ffffff")
    }

    func testParseSkipsBlankLines() {
        let content = """
        background = #000000

        foreground = #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Blanks", id: "blanks")
        XCTAssertNotNil(theme)
    }

    func testParseLinesWithoutEqualsAreSkipped() {
        let content = """
        background = #000000
        foreground = #ffffff
        this line has no equals sign
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoEq", id: "noeq")
        XCTAssertNotNil(theme)
    }

    // MARK: - Palette Parsing

    func testParsePaletteColors() {
        let content = """
        background = #000000
        foreground = #ffffff
        palette = 0=#111111
        palette = 1=#222222
        palette = 7=#777777
        palette = 8=#888888
        palette = 15=#ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Palette", id: "palette")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.black, "#111111")
        XCTAssertEqual(theme?.red, "#222222")
        XCTAssertEqual(theme?.white, "#777777")
        XCTAssertEqual(theme?.brightBlack, "#888888")
        XCTAssertEqual(theme?.brightWhite, "#ffffff")
    }

    func testParsePaletteWithoutHashPrefix() {
        let content = """
        background = #000000
        foreground = #ffffff
        palette = 0=1a1a1a
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoHash", id: "nohash")
        XCTAssertEqual(theme?.black, "#1a1a1a")
    }

    func testParsePaletteMissingIndicesGetDefaults() {
        let content = """
        background = #000000
        foreground = #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Defaults", id: "defaults")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.black, "#000000")
        XCTAssertEqual(theme?.red, "#CC0000")
        XCTAssertEqual(theme?.green, "#00CC00")
        XCTAssertEqual(theme?.yellow, "#CCCC00")
        XCTAssertEqual(theme?.blue, "#0000CC")
        XCTAssertEqual(theme?.magenta, "#CC00CC")
        XCTAssertEqual(theme?.cyan, "#00CCCC")
        XCTAssertEqual(theme?.white, "#CCCCCC")
        XCTAssertEqual(theme?.brightBlack, "#555555")
        XCTAssertEqual(theme?.brightRed, "#FF0000")
        XCTAssertEqual(theme?.brightGreen, "#00FF00")
        XCTAssertEqual(theme?.brightYellow, "#FFFF00")
        XCTAssertEqual(theme?.brightBlue, "#0000FF")
        XCTAssertEqual(theme?.brightMagenta, "#FF00FF")
        XCTAssertEqual(theme?.brightCyan, "#00FFFF")
        XCTAssertEqual(theme?.brightWhite, "#FFFFFF")
    }

    func testParsePaletteInvalidIndexIgnored() {
        let content = """
        background = #000000
        foreground = #ffffff
        palette = abc=#111111
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "BadIdx", id: "badidx")
        XCTAssertNotNil(theme)
        // palette entry with non-numeric index ignored, defaults used
        XCTAssertEqual(theme?.black, "#000000")
    }

    func testParsePaletteMalformedEntryNoEquals() {
        let content = """
        background = #000000
        foreground = #ffffff
        palette = 0#111111
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Malformed", id: "malformed")
        XCTAssertNotNil(theme)
        // Malformed palette entry skipped, defaults used
        XCTAssertEqual(theme?.black, "#000000")
    }

    // MARK: - Optional Fields

    func testParseCursorColorDefaultsToForeground() {
        let content = """
        background = #000000
        foreground = #abcdef
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoCursor", id: "nocursor")
        XCTAssertEqual(theme?.cursor, "#abcdef")
    }

    func testParseCursorColorExplicit() {
        let content = """
        background = #000000
        foreground = #ffffff
        cursor-color = #ff0000
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Cursor", id: "cursor")
        XCTAssertEqual(theme?.cursor, "#ff0000")
    }

    func testParseSelectionBackgroundDefaultsToForeground() {
        let content = """
        background = #000000
        foreground = #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoSel", id: "nosel")
        XCTAssertEqual(theme?.selectionBackground, "#ffffff")
    }

    func testParseSelectionForegroundIsOptional() {
        let content = """
        background = #000000
        foreground = #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoSelFg", id: "noselfg")
        XCTAssertNil(theme?.selectionForeground)
    }

    func testParseSelectionForegroundExplicit() {
        let content = """
        background = #000000
        foreground = #ffffff
        selection-foreground = #aabbcc
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "SelFg", id: "selfg")
        XCTAssertEqual(theme?.selectionForeground, "#aabbcc")
    }

    // MARK: - Hex Normalization

    func testNormalizationAddsHashToValidHex() {
        let content = """
        background = 1e1e1e
        foreground = d4d4d4
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "NoHash", id: "nohash")
        XCTAssertEqual(theme?.background, "#1e1e1e")
        XCTAssertEqual(theme?.foreground, "#d4d4d4")
    }

    func testNormalizationPreservesExistingHash() {
        let content = """
        background = #1e1e1e
        foreground = #d4d4d4
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Hash", id: "hash")
        XCTAssertEqual(theme?.background, "#1e1e1e")
    }

    func testNormalizationDoesNotAddHashToInvalidHex() {
        // A value that's not a 6-char hex string should not get # prepended
        let content = """
        background = #000000
        foreground = #ffffff
        cursor-color = rgb(255,0,0)
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Invalid", id: "invalid")
        XCTAssertEqual(theme?.cursor, "rgb(255,0,0)")
    }

    func testNormalizationDoesNotAddHashToShortString() {
        let content = """
        background = #000000
        foreground = #ffffff
        cursor-color = fff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Short", id: "short")
        XCTAssertEqual(theme?.cursor, "fff")
    }

    // MARK: - Whitespace Handling

    func testParseTrimsWhitespaceFromKeysAndValues() {
        let content = """
          background  =  #000000
          foreground  =  #ffffff
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Trimmed", id: "trimmed")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.background, "#000000")
        XCTAssertEqual(theme?.foreground, "#ffffff")
    }

    // MARK: - Full Theme

    func testParseFullThemeWithAllFields() {
        let content = """
        background = #1a1b26
        foreground = #c0caf5
        cursor-color = #e0af68
        cursor-text = #1a1b26
        selection-background = #33467c
        selection-foreground = #c0caf5
        palette = 0=#15161e
        palette = 1=#f7768e
        palette = 2=#9ece6a
        palette = 3=#e0af68
        palette = 4=#7aa2f7
        palette = 5=#bb9af7
        palette = 6=#7dcfff
        palette = 7=#a9b1d6
        palette = 8=#414868
        palette = 9=#f7768e
        palette = 10=#9ece6a
        palette = 11=#e0af68
        palette = 12=#7aa2f7
        palette = 13=#bb9af7
        palette = 14=#7dcfff
        palette = 15=#c0caf5
        """
        let theme = GhosttyThemeLoader.parse(content: content, name: "Tokyo Night", id: "ghostty-tokyo-night")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.background, "#1a1b26")
        XCTAssertEqual(theme?.cursor, "#e0af68")
        XCTAssertEqual(theme?.cursorText, "#1a1b26")
        XCTAssertEqual(theme?.selectionBackground, "#33467c")
        XCTAssertEqual(theme?.selectionForeground, "#c0caf5")
        XCTAssertEqual(theme?.black, "#15161e")
        XCTAssertEqual(theme?.red, "#f7768e")
        XCTAssertEqual(theme?.brightWhite, "#c0caf5")
    }

    // MARK: - Bundle Loading

    func testBundleLoadedThemesAreSortedByName() {
        // GhosttyThemeLoader.themes loads from main bundle.
        // In test target the bundle may not have themes, but the sorted
        // invariant should still hold (empty array is trivially sorted).
        let themes = GhosttyThemeLoader.themes
        let names = themes.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testBundleLoadedThemesHaveGhosttyIDPrefix() {
        for theme in GhosttyThemeLoader.themes {
            XCTAssertTrue(theme.id.hasPrefix("ghostty-"), "Theme '\(theme.name)' missing ghostty- prefix in id: \(theme.id)")
        }
    }

    func testBundleLoadedThemesHaveRequiredColors() {
        for theme in GhosttyThemeLoader.themes {
            XCTAssertFalse(theme.foreground.isEmpty, "Theme '\(theme.name)' has empty foreground")
            XCTAssertFalse(theme.background.isEmpty, "Theme '\(theme.name)' has empty background")
            XCTAssertFalse(theme.cursor.isEmpty, "Theme '\(theme.name)' has empty cursor")
        }
    }
}
