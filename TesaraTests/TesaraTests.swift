import XCTest
@testable import Tesara

final class TesaraTests: XCTestCase {
    func testDefaultSettingsUseTesaraTheme() {
        let settings = AppSettings.default

        XCTAssertEqual(settings.colorMode, .system)
        XCTAssertEqual(settings.darkThemeID, BuiltInTheme.tesaraDark.id)
        XCTAssertEqual(settings.lightThemeID, BuiltInTheme.tesaraLight.id)
        XCTAssertEqual(settings.defaultWorkingDirectory.path, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testBuiltInThemesCount() {
        XCTAssertEqual(BuiltInTheme.allCases.count, 22)
    }
}
