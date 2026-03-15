import XCTest
@testable import Tesara

final class ConfigFileWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("tesara-watcher-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeConfig(_ content: String) {
        try? content.write(to: tempDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    }

    // MARK: - Write Detection

    func testWatcherFiresCallbackOnFileWrite() {
        // Pre-create the config file so the watcher can open a file descriptor
        writeConfig("font-size = 13")

        let expectation = XCTestExpectation(description: "callback fired on write")

        let watcher = ConfigFileWatcher(directory: tempDir) {
            expectation.fulfill()
        }

        // Modify the file
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            self.writeConfig("font-size = 16")
        }

        wait(for: [expectation], timeout: 3)
        _ = watcher // keep alive
    }

    // MARK: - Rename/Delete Detection

    func testWatcherFiresCallbackOnFileRename() {
        writeConfig("font-size = 13")

        let expectation = XCTestExpectation(description: "callback fired on rename")

        let watcher = ConfigFileWatcher(directory: tempDir) {
            expectation.fulfill()
        }

        // Rename the file (simulating editors like vim that write to temp then rename)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            let configURL = self.tempDir.appendingPathComponent("config")
            let backupURL = self.tempDir.appendingPathComponent("config.bak")
            try? FileManager.default.moveItem(at: configURL, to: backupURL)
            try? FileManager.default.moveItem(at: backupURL, to: configURL)
        }

        wait(for: [expectation], timeout: 3)
        _ = watcher
    }

    // MARK: - No File

    func testWatcherHandlesMissingFileGracefully() {
        // Don't create the config file — watcher should not crash
        var callbackCount = 0
        let watcher = ConfigFileWatcher(directory: tempDir) {
            callbackCount += 1
        }

        // Give it a moment to confirm it doesn't fire spuriously
        let expectation = XCTestExpectation(description: "wait")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)

        XCTAssertEqual(callbackCount, 0)
        _ = watcher
    }

    // MARK: - Deallocation

    func testWatcherStopsOnDeinit() {
        writeConfig("font-size = 13")

        var callbackAfterDeinit = false
        var watcher: ConfigFileWatcher? = ConfigFileWatcher(directory: tempDir) {
            callbackAfterDeinit = true
        }
        watcher = nil // trigger deinit

        // Write after deinit — callback should not fire
        writeConfig("font-size = 16")

        let expectation = XCTestExpectation(description: "wait")
        expectation.isInverted = true
        wait(for: [expectation], timeout: 0.5)

        XCTAssertFalse(callbackAfterDeinit)
        _ = watcher
    }

    // MARK: - Multiple Writes

    func testWatcherFiresForConsecutiveWrites() {
        writeConfig("font-size = 13")

        let expectation = XCTestExpectation(description: "multiple callbacks")
        expectation.expectedFulfillmentCount = 2

        let watcher = ConfigFileWatcher(directory: tempDir) {
            expectation.fulfill()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            self.writeConfig("font-size = 14")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            self.writeConfig("font-size = 15")
        }

        wait(for: [expectation], timeout: 3)
        _ = watcher
    }
}
