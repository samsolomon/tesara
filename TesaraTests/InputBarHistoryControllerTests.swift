import XCTest
import GRDB
@testable import Tesara

@MainActor
final class InputBarHistoryControllerTests: XCTestCase {
    private var controller: InputBarHistoryController!
    private var blockStore: BlockStore!
    private var dbQueue: DatabaseQueue!
    private var inputBarState: InputBarState!

    override func setUp() async throws {
        try await super.setUp()
        controller = InputBarHistoryController()
        dbQueue = try DatabaseQueue()
        blockStore = try BlockStore(dbQueue: dbQueue)
        controller.blockStore = blockStore
        inputBarState = InputBarState()
    }

    // MARK: - Helpers

    /// Write a command directly to the database, bypassing the async dispatch
    /// in `BlockStore.recordBlock` to avoid race conditions in tests.
    private func recordCommand(_ text: String) {
        let sessionID = UUID().uuidString
        let blockID = UUID().uuidString
        let now = Date()
        try! dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO terminal_sessions (id, shellPath, workingDirectory, startedAt)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [sessionID, "/bin/zsh", "/tmp", now]
            )
            try db.execute(
                sql: """
                INSERT INTO terminal_blocks (id, sessionID, orderIndex, commandText, outputText, exitCode, startedAt, finishedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [blockID, sessionID, 0, text, "", 0, now, now]
            )
        }
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(controller.isSearchActive)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertEqual(controller.selectedSearchIndex, 0)
        XCTAssertFalse(controller.isPopupActive)
        XCTAssertTrue(controller.popupItems.isEmpty)
        XCTAssertEqual(controller.selectedPopupIndex, 0)
    }

    // MARK: - History Popup

    func testOpenPopupWithEmptyHistoryIsNoOp() {
        inputBarState.setText("current")
        controller.openPopup(currentText: "current", inputBarState: inputBarState)
        XCTAssertFalse(controller.isPopupActive)
        XCTAssertEqual(inputBarState.currentText(), "current")
    }

    func testOpenPopupShowsItems() {
        recordCommand("ls -la")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        XCTAssertTrue(controller.isPopupActive)
        guard !controller.popupItems.isEmpty else { return XCTFail("Expected popup items") }
        XCTAssertEqual(controller.selectedPopupIndex, 0)
        XCTAssertEqual(inputBarState.currentText(), controller.popupItems[0])
    }

    func testDismissPopupRestoresInput() {
        recordCommand("ls -la")
        inputBarState.setText("ls")
        controller.openPopup(currentText: "ls", inputBarState: inputBarState)
        // After opening, input bar should show first matching item
        XCTAssertTrue(controller.isPopupActive)
        controller.dismissPopup(inputBarState: inputBarState)
        XCTAssertFalse(controller.isPopupActive)
        XCTAssertEqual(inputBarState.currentText(), "ls")
    }

    func testPopupSelectPreviousClampsAtZero() {
        recordCommand("first")
        recordCommand("second")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        XCTAssertEqual(controller.selectedPopupIndex, 0)
        controller.popupSelectPrevious(inputBarState: inputBarState)
        XCTAssertEqual(controller.selectedPopupIndex, 0)
    }

    func testPopupSelectNextClampsAtEnd() {
        recordCommand("only")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        XCTAssertEqual(controller.popupItems.count, 1)
        controller.popupSelectNext(inputBarState: inputBarState)
        XCTAssertEqual(controller.selectedPopupIndex, 0)
    }

    func testOpenPopupWithPrefixFilter() {
        recordCommand("git status")
        recordCommand("ls -la")
        recordCommand("git push")
        inputBarState.setText("git")
        controller.openPopup(currentText: "git", inputBarState: inputBarState)
        XCTAssertTrue(controller.isPopupActive)
        for item in controller.popupItems {
            XCTAssertTrue(item.hasPrefix("git"))
        }
    }

    func testOpenPopupWithNilBlockStoreIsNoOp() {
        controller.blockStore = nil
        inputBarState.setText("test")
        controller.openPopup(currentText: "test", inputBarState: inputBarState)
        XCTAssertFalse(controller.isPopupActive)
        XCTAssertEqual(inputBarState.currentText(), "test")
    }

    func testPopupMaxTenItems() {
        for i in 0..<15 {
            recordCommand("cmd\(i)")
        }
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        XCTAssertTrue(controller.isPopupActive)
        XCTAssertLessThanOrEqual(controller.popupItems.count, 10)
    }

    func testAcceptPopupSelection() {
        recordCommand("first")
        recordCommand("second")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        guard !controller.popupItems.isEmpty else { return XCTFail("Expected popup items") }
        let selectedCommand = controller.popupItems[controller.selectedPopupIndex]
        controller.acceptPopupSelection()
        XCTAssertFalse(controller.isPopupActive)
        // Input bar should still contain the selected command (not restored)
        XCTAssertEqual(inputBarState.currentText(), selectedCommand)
    }

    func testResetDismissesPopup() {
        recordCommand("ls -la")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        XCTAssertTrue(controller.isPopupActive)
        controller.reset()
        XCTAssertFalse(controller.isPopupActive)
        XCTAssertTrue(controller.popupItems.isEmpty)
    }

    func testPopupPreviewsSelectedItem() {
        recordCommand("first")
        recordCommand("second")
        inputBarState.setText("")
        controller.openPopup(currentText: "", inputBarState: inputBarState)
        guard !controller.popupItems.isEmpty else { return XCTFail("Expected popup items") }
        let firstItem = controller.popupItems[0]
        XCTAssertEqual(inputBarState.currentText(), firstItem)
        guard controller.popupItems.count > 1 else { return }
        controller.popupSelectNext(inputBarState: inputBarState)
        let secondItem = controller.popupItems[1]
        XCTAssertEqual(inputBarState.currentText(), secondItem)
    }

    // MARK: - Search (Ctrl+R)

    func testBeginSearchActivatesSearch() {
        controller.beginSearch()
        XCTAssertTrue(controller.isSearchActive)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }

    func testUpdateSearchFindsResults() {
        recordCommand("git status")
        recordCommand("git push origin main")
        controller.beginSearch()
        controller.updateSearch(query: "git")
        XCTAssertFalse(controller.searchResults.isEmpty)
        for result in controller.searchResults {
            XCTAssertTrue(result.contains("git"))
        }
    }

    func testUpdateSearchEmptyQueryClearsResults() {
        recordCommand("git status")
        controller.beginSearch()
        controller.updateSearch(query: "git")
        // Even if async writes haven't completed, empty query should always clear
        controller.updateSearch(query: "")
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertEqual(controller.selectedSearchIndex, 0)
    }

    func testSearchNoMatchesReturnsEmpty() {
        recordCommand("git status")
        controller.beginSearch()
        controller.updateSearch(query: "zzzznonexistent")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }

    func testAcceptSearchResult() {
        recordCommand("git status")
        controller.beginSearch()
        controller.updateSearch(query: "git")
        guard !controller.searchResults.isEmpty else { return XCTFail("Expected results") }
        controller.acceptSearchResult(inputBarState: inputBarState)
        XCTAssertFalse(controller.isSearchActive)
        XCTAssertTrue(inputBarState.currentText().contains("git"))
    }

    func testAcceptSearchResultWithNoResultsCancels() {
        controller.beginSearch()
        controller.acceptSearchResult(inputBarState: inputBarState)
        XCTAssertFalse(controller.isSearchActive)
    }

    func testCancelSearch() {
        controller.beginSearch()
        controller.updateSearch(query: "test")
        controller.cancelSearch()
        XCTAssertFalse(controller.isSearchActive)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        controller.beginSearch()
        controller.updateSearch(query: "test")
        controller.reset()
        XCTAssertFalse(controller.isSearchActive)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }

    // MARK: - Nil BlockStore

    func testSearchWithNilBlockStoreReturnsEmpty() {
        controller.blockStore = nil
        controller.beginSearch()
        controller.updateSearch(query: "anything")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }
}
