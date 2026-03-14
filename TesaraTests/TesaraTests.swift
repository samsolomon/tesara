import XCTest
@testable import Tesara

final class TesaraTests: XCTestCase {
    func testDefaultSettingsUseOxideTheme() {
        let settings = AppSettings.default

        XCTAssertEqual(settings.colorMode, .system)
        XCTAssertEqual(settings.darkThemeID, BuiltInTheme.oxide.id)
        XCTAssertEqual(settings.defaultWorkingDirectory.path, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testBuiltInThemesCount() {
        XCTAssertEqual(BuiltInTheme.allCases.count, 10)
    }
}
