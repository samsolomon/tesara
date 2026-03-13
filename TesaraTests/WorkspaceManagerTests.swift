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
        blockStore = try BlockStore(dbQueue: DatabaseQueue())
    }

    private func addTab() {
        manager.newTab(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
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
}
