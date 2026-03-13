import XCTest
import GRDB
@testable import Tesara

@MainActor
final class WorkspaceManagerTests: XCTestCase {
    private var manager: WorkspaceManager!
    private var blockStore: BlockStore!

    override func setUp() async throws {
        try await super.setUp()
        manager = WorkspaceManager()
        manager.sessionFactory = { TerminalSession() }
        manager.setConfirmOnCloseRunningSessionEnabled(false)
        blockStore = try BlockStore(dbQueue: DatabaseQueue())
    }

    private func addTab() {
        manager.newTab(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
    }

    private func waitForWorkspaceRefresh() {
        let expectation = XCTestExpectation(description: "workspace refresh")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    // MARK: Tab Creation

    func testNewTabCreatesAndActivates() {
        addTab()
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.activeTabID, manager.tabs[0].id)
    }

    func testMultipleTabsActiveIsLast() {
        addTab()
        addTab()
        addTab()
        XCTAssertEqual(manager.tabs.count, 3)
        XCTAssertEqual(manager.activeTabID, manager.tabs[2].id)
    }

    func testNewTabUsesWorkingDirectoryTitle() {
        addTab()
        XCTAssertEqual(manager.tabs.first?.title, "tmp")
    }

    func testTabTitleUsesWorkingDirectoryWhenAvailable() throws {
        addTab()

        let session = try XCTUnwrap(manager.activeSession)
        session.updateWorkingDirectory(URL(fileURLWithPath: "/Users/tester/Documents/playground"))
        waitForWorkspaceRefresh()

        XCTAssertEqual(manager.tabs.first?.title, "playground")
    }

    func testTabTitleUsesShellTitleOverWorkingDirectory() throws {
        addTab()

        let session = try XCTUnwrap(manager.activeSession)
        session.updateWorkingDirectory(URL(fileURLWithPath: "/Users/tester/Documents/playground"))
        session.updateTitle("Deploy logs")
        waitForWorkspaceRefresh()

        XCTAssertEqual(manager.tabs.first?.title, "Deploy logs")
    }

    // MARK: Tab Closing

    func testCloseActiveTabSelectsNext() {
        addTab()
        addTab()
        addTab()
        let firstID = manager.tabs[0].id
        let secondID = manager.tabs[1].id

        manager.selectTab(id: firstID)
        manager.closeTab(id: firstID)

        XCTAssertEqual(manager.tabs.count, 2)
        XCTAssertEqual(manager.activeTabID, secondID)
    }

    func testCloseLastTabSelectsPrevious() {
        addTab()
        addTab()
        let lastID = manager.tabs[1].id
        let firstID = manager.tabs[0].id

        manager.selectTab(id: lastID)
        manager.closeTab(id: lastID)

        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.activeTabID, firstID)
    }

    func testCloseOnlyTabClearsActiveID() {
        addTab()
        let id = manager.tabs[0].id
        manager.closeTab(id: id)

        XCTAssertTrue(manager.tabs.isEmpty)
        XCTAssertNil(manager.activeTabID)
        XCTAssertNil(manager.activePaneID)
    }

    func testCloseNonExistentTabIsNoOp() {
        addTab()
        let count = manager.tabs.count
        manager.closeTab(id: UUID())
        XCTAssertEqual(manager.tabs.count, count)
    }

    func testCloseRunningPaneRequiresConfirmationWhenEnabled() throws {
        manager.setConfirmOnCloseRunningSessionEnabled(true)
        addTab()

        let paneID = try XCTUnwrap(manager.activePaneID)
        let session = try XCTUnwrap(manager.activeSession)
        session.setStatusForTesting(.running)

        manager.closePane(id: paneID)

        XCTAssertEqual(manager.pendingCloseConfirmation, .runningPane(paneID))
        XCTAssertEqual(manager.tabs.count, 1)
    }

    func testResolveRunningPaneConfirmationClosesPane() throws {
        manager.setConfirmOnCloseRunningSessionEnabled(true)
        addTab()

        let paneID = try XCTUnwrap(manager.activePaneID)
        let session = try XCTUnwrap(manager.activeSession)
        session.setStatusForTesting(.running)

        manager.closePane(id: paneID)
        manager.resolvePendingClose(.discard)

        XCTAssertTrue(manager.tabs.isEmpty)
        XCTAssertNil(manager.pendingCloseConfirmation)
        XCTAssertNil(manager.activeTabID)
        XCTAssertNil(manager.activePaneID)
    }

    func testCloseRunningTabRequiresConfirmationWhenEnabled() throws {
        manager.setConfirmOnCloseRunningSessionEnabled(true)
        addTab()

        let tabID = try XCTUnwrap(manager.activeTabID)
        let session = try XCTUnwrap(manager.activeSession)
        session.setStatusForTesting(.running)

        manager.closeTab(id: tabID)

        XCTAssertEqual(manager.pendingCloseConfirmation, .runningTab(tabID))
        XCTAssertEqual(manager.tabs.count, 1)
    }

    func testCloseRunningPaneBypassesConfirmationWhenDisabled() throws {
        addTab()

        let paneID = try XCTUnwrap(manager.activePaneID)
        let session = try XCTUnwrap(manager.activeSession)
        session.setStatusForTesting(.running)

        manager.closePane(id: paneID)

        XCTAssertTrue(manager.tabs.isEmpty)
        XCTAssertNil(manager.pendingCloseConfirmation)
    }

    func testSelectingTabRestoresItsSelectedPane() {
        addTab()
        let firstTabID = manager.tabs[0].id
        let firstTabPaneID = manager.tabs[0].selectedPaneID

        addTab()
        let secondTabID = manager.tabs[1].id

        manager.selectTab(id: firstTabID)
        XCTAssertEqual(manager.activePaneID, firstTabPaneID)

        manager.selectTab(id: secondTabID)
        XCTAssertEqual(manager.activePaneID, manager.tabs[1].selectedPaneID)
    }

    // MARK: Tab Switching

    func testSelectTabByID() {
        addTab()
        addTab()
        let firstID = manager.tabs[0].id
        manager.selectTab(id: firstID)
        XCTAssertEqual(manager.activeTabID, firstID)
    }

    func testSelectTabByIndex() {
        addTab()
        addTab()
        addTab()
        manager.selectTab(atIndex: 1)
        XCTAssertEqual(manager.activeTabID, manager.tabs[1].id)
    }

    func testSelectTabByInvalidIndexIsNoOp() {
        addTab()
        let activeID = manager.activeTabID
        manager.selectTab(atIndex: 5)
        XCTAssertEqual(manager.activeTabID, activeID)
    }

    func testSelectTabByNegativeIndexIsNoOp() {
        addTab()
        let activeID = manager.activeTabID
        manager.selectTab(atIndex: -1)
        XCTAssertEqual(manager.activeTabID, activeID)
    }

    func testSelectNonExistentIDIsNoOp() {
        addTab()
        let activeID = manager.activeTabID
        manager.selectTab(id: UUID())
        XCTAssertEqual(manager.activeTabID, activeID)
    }

    // MARK: Previous/Next

    func testSelectPreviousTab() {
        addTab()
        addTab()
        addTab()
        manager.selectPreviousTab()
        XCTAssertEqual(manager.activeTabID, manager.tabs[1].id)
    }

    func testSelectPreviousTabWrapsToEnd() {
        addTab()
        addTab()
        manager.selectTab(atIndex: 0)
        manager.selectPreviousTab()
        XCTAssertEqual(manager.activeTabID, manager.tabs[1].id)
    }

    func testSelectNextTab() {
        addTab()
        addTab()
        addTab()
        manager.selectTab(atIndex: 0)
        manager.selectNextTab()
        XCTAssertEqual(manager.activeTabID, manager.tabs[1].id)
    }

    func testSelectNextTabWrapsToStart() {
        addTab()
        addTab()
        manager.selectNextTab()
        XCTAssertEqual(manager.activeTabID, manager.tabs[0].id)
    }

    // MARK: Tab Reordering

    func testMoveTab() {
        addTab()
        addTab()
        addTab()
        let ids = manager.tabs.map(\.id)
        manager.moveTab(from: 0, to: 2)
        XCTAssertEqual(manager.tabs[0].id, ids[1])
    }

    func testMoveTabSameIndexIsNoOp() {
        addTab()
        addTab()
        let ids = manager.tabs.map(\.id)
        manager.moveTab(from: 1, to: 1)
        XCTAssertEqual(manager.tabs.map(\.id), ids)
    }

    func testMoveTabOutOfBoundsIsNoOp() {
        addTab()
        addTab()
        let ids = manager.tabs.map(\.id)
        manager.moveTab(from: 0, to: 5)
        XCTAssertEqual(manager.tabs.map(\.id), ids)
    }

    // MARK: Active Tab

    func testActiveTabReturnsCorrectTab() {
        addTab()
        addTab()
        manager.selectTab(atIndex: 0)
        XCTAssertEqual(manager.activeTab?.id, manager.tabs[0].id)
    }

    func testActiveTabReturnsNilWhenEmpty() {
        XCTAssertNil(manager.activeTab)
    }

    // MARK: Active Pane

    func testNewTabSetsActivePaneID() {
        addTab()
        XCTAssertNotNil(manager.activePaneID)
    }

    func testActiveSessionReturnsSession() {
        addTab()
        XCTAssertNotNil(manager.activeSession)
    }

    // MARK: Split Panes

    func testSplitActivePaneCreatesSecondPane() {
        addTab()
        let initialPaneID = manager.activePaneID
        manager.splitActivePane(
            direction: .horizontal,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        XCTAssertNotEqual(manager.activePaneID, initialPaneID)
        if case .split = manager.activeTab?.rootPane {
            // success
        } else {
            XCTFail("Expected split root pane after splitting")
        }
    }

    func testClosePanePromotesSibling() {
        addTab()
        let firstPaneID = manager.activePaneID!
        manager.splitActivePane(
            direction: .horizontal,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let newPaneID = manager.activePaneID!

        manager.closePane(id: newPaneID)
        XCTAssertEqual(manager.activePaneID, firstPaneID)
        if case .leaf = manager.activeTab?.rootPane {
            // success
        } else {
            XCTFail("Expected leaf root pane after closing split pane")
        }
    }

    func testSelectPane() {
        addTab()
        let firstPaneID = manager.activePaneID!
        manager.splitActivePane(
            direction: .horizontal,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let secondPaneID = manager.activePaneID!

        manager.selectPane(id: firstPaneID)
        XCTAssertEqual(manager.activePaneID, firstPaneID)

        manager.selectPane(id: secondPaneID)
        XCTAssertEqual(manager.activePaneID, secondPaneID)
    }

    func testSelectPaneSameIDIsNoOp() {
        addTab()
        let paneID = manager.activePaneID!
        // Calling selectPane with the already-active pane should be a no-op
        manager.selectPane(id: paneID)
        XCTAssertEqual(manager.activePaneID, paneID)
    }

    func testSelectPaneUpdatesActivePaneAfterSplit() {
        addTab()
        let firstPaneID = manager.activePaneID!
        manager.splitActivePane(
            direction: .vertical,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let secondPaneID = manager.activePaneID!
        XCTAssertNotEqual(firstPaneID, secondPaneID)

        // Switch back to first pane
        manager.selectPane(id: firstPaneID)
        XCTAssertEqual(manager.activePaneID, firstPaneID)

        // Verify active session corresponds to the selected pane
        XCTAssertNotNil(manager.activeSession)
    }

    // MARK: - Editor Panes

    func testSplitWithEditorCreatesEditorPane() {
        addTab()
        let initialPaneID = manager.activePaneID!
        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: TerminalTheme(
                id: "test", name: "Test",
                foreground: "#cccccc", background: "#1e1e1e",
                cursor: "#cccccc", cursorText: "#1e1e1e",
                selectionBackground: "#3c5a96",
                black: "#000000", red: "#ff0000", green: "#00ff00",
                yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
                cyan: "#00ffff", white: "#ffffff",
                brightBlack: "#808080", brightRed: "#ff0000",
                brightGreen: "#00ff00", brightYellow: "#ffff00",
                brightBlue: "#0000ff", brightMagenta: "#ff00ff",
                brightCyan: "#00ffff", brightWhite: "#ffffff"
            ),
            fontFamily: "SF Mono",
            fontSize: 13
        )
        XCTAssertNotEqual(manager.activePaneID, initialPaneID)
        // Active pane should be the editor
        XCTAssertNotNil(manager.activeEditorSession)
        XCTAssertNil(manager.activeSession) // Not a terminal
    }

    func testCloseEditorPane() {
        addTab()
        let termPaneID = manager.activePaneID!
        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: TerminalTheme(
                id: "test", name: "Test",
                foreground: "#cccccc", background: "#1e1e1e",
                cursor: "#cccccc", cursorText: "#1e1e1e",
                selectionBackground: "#3c5a96",
                black: "#000000", red: "#ff0000", green: "#00ff00",
                yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
                cyan: "#00ffff", white: "#ffffff",
                brightBlack: "#808080", brightRed: "#ff0000",
                brightGreen: "#00ff00", brightYellow: "#ffff00",
                brightBlue: "#0000ff", brightMagenta: "#ff00ff",
                brightCyan: "#00ffff", brightWhite: "#ffffff"
            ),
            fontFamily: "SF Mono",
            fontSize: 13
        )
        let editorPaneID = manager.activePaneID!

        manager.closePane(id: editorPaneID)
        XCTAssertEqual(manager.activePaneID, termPaneID)
        if case .leaf = manager.activeTab?.rootPane {
            // success
        } else {
            XCTFail("Expected leaf root pane after closing editor")
        }
    }

    func testSelectBetweenTerminalAndEditor() {
        addTab()
        let termPaneID = manager.activePaneID!
        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: TerminalTheme(
                id: "test", name: "Test",
                foreground: "#cccccc", background: "#1e1e1e",
                cursor: "#cccccc", cursorText: "#1e1e1e",
                selectionBackground: "#3c5a96",
                black: "#000000", red: "#ff0000", green: "#00ff00",
                yellow: "#ffff00", blue: "#0000ff", magenta: "#ff00ff",
                cyan: "#00ffff", white: "#ffffff",
                brightBlack: "#808080", brightRed: "#ff0000",
                brightGreen: "#00ff00", brightYellow: "#ffff00",
                brightBlue: "#0000ff", brightMagenta: "#ff00ff",
                brightCyan: "#00ffff", brightWhite: "#ffffff"
            ),
            fontFamily: "SF Mono",
            fontSize: 13
        )
        let editorPaneID = manager.activePaneID!

        // Switch to terminal
        manager.selectPane(id: termPaneID)
        XCTAssertEqual(manager.activePaneID, termPaneID)
        XCTAssertNotNil(manager.activeSession)
        XCTAssertNil(manager.activeEditorSession)

        // Switch back to editor
        manager.selectPane(id: editorPaneID)
        XCTAssertEqual(manager.activePaneID, editorPaneID)
        XCTAssertNil(manager.activeSession)
        XCTAssertNotNil(manager.activeEditorSession)
    }
}
