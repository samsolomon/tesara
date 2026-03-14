import XCTest
@testable import Tesara

final class FixedPitchFontLibraryTests: XCTestCase {
    private let families = ["JetBrains Mono", "Menlo", "SF Mono"]

    func testNormalizeRemovesBlanksDuplicatesAndSorts() {
        let families = FixedPitchFontLibrary.normalize([
            " Menlo ",
            "SF Mono",
            "",
            "menlo",
            "JetBrains Mono",
            "SF Mono"
        ])

        XCTAssertEqual(families, ["JetBrains Mono", "Menlo", "SF Mono"])
    }

    func testFilterReturnsAllFamiliesWhenQueryIsEmpty() {
        let families = FixedPitchFontLibrary.filter(["SF Mono", "Menlo", "JetBrains Mono"], query: "   ")
        XCTAssertEqual(families, ["JetBrains Mono", "Menlo", "SF Mono"])
    }

    func testFilterMatchesCaseInsensitiveSubstring() {
        let families = FixedPitchFontLibrary.filter(["SF Mono", "Menlo", "JetBrains Mono"], query: "mono")
        XCTAssertEqual(families, ["JetBrains Mono", "SF Mono"])
    }

    func testContainsMatchesCaseInsensitiveFamilyName() {
        XCTAssertTrue(FixedPitchFontLibrary.contains("sf mono", in: ["SF Mono", "Menlo"]))
        XCTAssertFalse(FixedPitchFontLibrary.contains("Monaco", in: ["SF Mono", "Menlo"]))
    }

    func testNavigationReconcilesToCurrentSelectionWhenAvailable() {
        let highlighted = FixedPitchFontNavigation.reconciledHighlight(
            current: nil,
            selection: "sf mono",
            in: families
        )

        XCTAssertEqual(highlighted, "SF Mono")
    }

    func testNavigationFallsBackToFirstFamilyWhenSelectionMissing() {
        let highlighted = FixedPitchFontNavigation.reconciledHighlight(
            current: nil,
            selection: "Monaco",
            in: families
        )

        XCTAssertEqual(highlighted, "JetBrains Mono")
    }

    func testMoveDownAdvancesToNextFamily() {
        let next = FixedPitchFontNavigation.move(
            current: "Menlo",
            direction: .down,
            in: families
        )

        XCTAssertEqual(next, "SF Mono")
    }

    func testMoveUpStopsAtFirstFamily() {
        let previous = FixedPitchFontNavigation.move(
            current: "JetBrains Mono",
            direction: .up,
            in: families
        )

        XCTAssertEqual(previous, "JetBrains Mono")
    }

    func testSelectionToApplyUsesHighlightedFamily() {
        let applied = FixedPitchFontNavigation.selectionToApply(
            highlighted: "menlo",
            in: families
        )

        XCTAssertEqual(applied, "Menlo")
    }
}
