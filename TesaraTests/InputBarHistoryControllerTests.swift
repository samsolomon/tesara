import XCTest
import GRDB
@testable import Tesara

@MainActor
final class InputBarHistoryControllerTests: XCTestCase {
    private var controller: InputBarHistoryController!
    private var blockStore: BlockStore!
    private var inputBarState: InputBarState!

    override func setUp() async throws {
        try await super.setUp()
        controller = InputBarHistoryController()
        blockStore = try BlockStore(dbQueue: DatabaseQueue())
        controller.blockStore = blockStore
        inputBarState = InputBarState()
    }

    // MARK: - Helpers

    private func recordCommand(_ text: String) {
        let sessionID = blockStore.startSession(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        let block = TerminalBlockCapture(
            commandText: text,
            outputText: "",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            stage: .output
        )
        blockStore.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        waitForAsyncWrites()
    }

    private func waitForAsyncWrites() {
        let expectation = XCTestExpectation(description: "async writes")
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.global(qos: .utility).async {
                DispatchQueue.main.async { expectation.fulfill() }
            }
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertFalse(controller.isSearchActive)
        XCTAssertEqual(controller.searchQuery, "")
        XCTAssertTrue(controller.searchResults.isEmpty)
        XCTAssertEqual(controller.selectedSearchIndex, 0)
    }

    // MARK: - Up/Down Navigation

    func testNavigateUpWithNoHistoryIsNoOp() {
        inputBarState.setText("current")
        controller.navigateUp(currentText: "current", inputBarState: inputBarState)
        XCTAssertEqual(inputBarState.currentText(), "current")
    }

    func testNavigateUpShowsHistory() {
        recordCommand("ls -la")
        inputBarState.setText("")
        controller.navigateUp(currentText: "", inputBarState: inputBarState)
        XCTAssertEqual(inputBarState.currentText(), "ls -la")
    }

    func testNavigateUpThenDownRestoresInput() {
        recordCommand("ls -la")
        inputBarState.setText("typed")
        controller.navigateUp(currentText: "typed", inputBarState: inputBarState)
        let afterUp = inputBarState.currentText()
        // After navigating up, should show a history entry
        XCTAssertFalse(afterUp.isEmpty)
        controller.navigateDown(currentText: afterUp, inputBarState: inputBarState)
        // After navigating back down, should restore saved input
        XCTAssertEqual(inputBarState.currentText(), "typed")
    }

    func testNavigateDownWithNoHistoryIsNoOp() {
        inputBarState.setText("current")
        controller.navigateDown(currentText: "current", inputBarState: inputBarState)
        XCTAssertEqual(inputBarState.currentText(), "current")
    }

    func testNavigateUpStopsAtEnd() {
        recordCommand("only")
        inputBarState.setText("")
        controller.navigateUp(currentText: "", inputBarState: inputBarState)
        controller.navigateUp(currentText: inputBarState.currentText(), inputBarState: inputBarState)
        XCTAssertEqual(inputBarState.currentText(), "only")
    }

    func testNavigateUpWithPrefixFilter() {
        recordCommand("git status")
        recordCommand("ls -la")
        recordCommand("git push")
        inputBarState.setText("git")
        controller.navigateUp(currentText: "git", inputBarState: inputBarState)
        XCTAssertTrue(inputBarState.currentText().hasPrefix("git"))
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

    func testNavigateUpWithNilBlockStoreIsNoOp() {
        controller.blockStore = nil
        inputBarState.setText("test")
        controller.navigateUp(currentText: "test", inputBarState: inputBarState)
        XCTAssertEqual(inputBarState.currentText(), "test")
    }

    func testSearchWithNilBlockStoreReturnsEmpty() {
        controller.blockStore = nil
        controller.beginSearch()
        controller.updateSearch(query: "anything")
        XCTAssertTrue(controller.searchResults.isEmpty)
    }
}
