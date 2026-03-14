import XCTest
import GRDB
@testable import Tesara

@MainActor
final class WorkspaceManagerTests: XCTestCase {
    private var manager: WorkspaceManager!
    private var blockStore: BlockStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        manager = WorkspaceManager()
        manager.sessionFactory = { TerminalSession() }
        manager.setConfirmOnCloseRunningSessionEnabled(false)
        blockStore = try BlockStore(dbQueue: DatabaseQueue())
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
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

    private func tempFile(name: String, content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
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

    func testDirtyPaneSaveWaitsForSavePanelBeforeClosing() throws {
        addTab()
        let terminalPaneID = try XCTUnwrap(manager.activePaneID)

        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: testTheme,
            fontFamily: "SF Mono",
            fontSize: 13
        )

        let editorPaneID = try XCTUnwrap(manager.activePaneID)
        let editorSession = try XCTUnwrap(manager.activeEditorSession)
        editorSession.insertText("hello")

        manager.closePane(id: editorPaneID)
        XCTAssertEqual(manager.pendingCloseConfirmation, .dirtyPane(editorPaneID))

        manager.resolvePendingClose(.save)
        XCTAssertEqual(manager.pendingSavePanel, editorSession.id)
        XCTAssertNotNil(manager.activeTab?.rootPane.findEditorSession(forPaneID: editorPaneID))

        let url = tempDir.appendingPathComponent("pane-save.txt")
        manager.completePendingSavePanel(sessionID: editorSession.id, url: url)

        XCTAssertEqual(manager.activePaneID, terminalPaneID)
        XCTAssertNil(manager.activeTab?.rootPane.findEditorSession(forPaneID: editorPaneID))
    }

    func testCloseDirtyTabRequestsConfirmation() throws {
        addTab()
        let tabID = try XCTUnwrap(manager.activeTabID)

        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: testTheme,
            fontFamily: "SF Mono",
            fontSize: 13
        )

        let editorSession = try XCTUnwrap(manager.activeEditorSession)
        editorSession.insertText("unsaved")

        manager.closeTab(id: tabID)

        XCTAssertEqual(manager.pendingCloseConfirmation, .dirtyTab(tabID))
        XCTAssertEqual(manager.tabs.count, 1)
    }

    func testDirtyTabSaveWaitsForSavePanelBeforeClosing() throws {
        addTab()
        let tabID = try XCTUnwrap(manager.activeTabID)

        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: testTheme,
            fontFamily: "SF Mono",
            fontSize: 13
        )

        let editorSession = try XCTUnwrap(manager.activeEditorSession)
        editorSession.insertText("unsaved")

        manager.closeTab(id: tabID)
        manager.resolvePendingClose(.save)

        XCTAssertEqual(manager.pendingSavePanel, editorSession.id)
        XCTAssertEqual(manager.tabs.count, 1)

        let url = tempDir.appendingPathComponent("tab-save.txt")
        manager.completePendingSavePanel(sessionID: editorSession.id, url: url)

        XCTAssertTrue(manager.tabs.isEmpty)
        XCTAssertNil(manager.pendingSavePanel)
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

    // MARK: - Target-Aware Lookup

    func testTabAndPaneIDFindsCorrectTab() throws {
        addTab()
        addTab()
        let firstSession = try XCTUnwrap(manager.tabs[0].rootPane.session)
        let secondSession = try XCTUnwrap(manager.tabs[1].rootPane.session)

        let result1 = manager.tabAndPaneID(for: firstSession)
        XCTAssertEqual(result1?.tabID, manager.tabs[0].id)
        XCTAssertEqual(result1?.paneID, manager.tabs[0].rootPane.id)

        let result2 = manager.tabAndPaneID(for: secondSession)
        XCTAssertEqual(result2?.tabID, manager.tabs[1].id)
        XCTAssertEqual(result2?.paneID, manager.tabs[1].rootPane.id)
    }

    func testTabAndPaneIDReturnsNilForUnknownSession() {
        addTab()
        let orphan = TerminalSession()
        XCTAssertNil(manager.tabAndPaneID(for: orphan))
    }

    // MARK: - GhosttyActionDelegate

    func testGhosttyNewTabInheritsWorkingDirectory() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()

        let session = try XCTUnwrap(manager.activeSession)
        session.updateWorkingDirectory(URL(fileURLWithPath: "/Users/tester/projects"))

        manager.ghosttyNewTab(inheritingFrom: session)
        XCTAssertEqual(manager.tabs.count, 2)
    }

    func testGhosttyNewTabFallsBackToDefault() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore

        manager.ghosttyNewTab(inheritingFrom: nil)
        XCTAssertEqual(manager.tabs.count, 1)
    }

    func testGhosttyCloseTabClosesCorrectTab() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()
        addTab()

        let firstSession = try XCTUnwrap(manager.tabs[0].rootPane.session)
        let secondTabID = manager.tabs[1].id

        manager.ghosttyCloseTab(for: firstSession)
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.tabs[0].id, secondTabID)
    }

    func testGhosttyClosePaneClosesCorrectPane() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()

        let firstPaneID = try XCTUnwrap(manager.activePaneID)
        manager.splitActivePane(
            direction: .horizontal,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let secondPaneID = try XCTUnwrap(manager.activePaneID)
        let secondSession = try XCTUnwrap(manager.activeSession)

        manager.ghosttyClosePane(for: secondSession)
        XCTAssertEqual(manager.activePaneID, firstPaneID)
        if case .leaf = manager.activeTab?.rootPane {
            // success — split collapsed back to leaf
        } else {
            XCTFail("Expected leaf root pane after closing split pane")
        }
    }

    func testGhosttyCloseOtherTabsKeepsOnlyTargetTab() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()
        addTab()
        addTab()

        let middleSession = try XCTUnwrap(manager.tabs[1].rootPane.session)
        let middleTabID = manager.tabs[1].id

        manager.ghosttyCloseOtherTabs(for: middleSession)
        XCTAssertEqual(manager.tabs.count, 1)
        XCTAssertEqual(manager.tabs[0].id, middleTabID)
    }

    func testGhosttyCloseTabsToRightKeepsLeftTabs() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()
        addTab()
        addTab()
        addTab()

        let secondSession = try XCTUnwrap(manager.tabs[1].rootPane.session)
        let firstTabID = manager.tabs[0].id
        let secondTabID = manager.tabs[1].id

        manager.ghosttyCloseTabsToRight(of: secondSession)
        XCTAssertEqual(manager.tabs.count, 2)
        XCTAssertEqual(manager.tabs[0].id, firstTabID)
        XCTAssertEqual(manager.tabs[1].id, secondTabID)
    }

    func testGhosttySplitFirstPositionPutsNewPaneFirst() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()

        let session = try XCTUnwrap(manager.activeSession)
        let originalPaneID = try XCTUnwrap(manager.activePaneID)

        manager.ghosttySplit(for: session, direction: .horizontal, newPanePosition: .first)

        // Active pane should be the new pane (which is now `first` in the split)
        XCTAssertNotEqual(manager.activePaneID, originalPaneID)

        guard case .split(_, _, let first, let second, _) = manager.activeTab?.rootPane else {
            XCTFail("Expected split root pane")
            return
        }
        // The new pane is .first, the original is .second
        XCTAssertEqual(second.id, originalPaneID)
        XCTAssertNotEqual(first.id, originalPaneID)
    }

    func testGhosttyRequestQuitBlocksWhenDirtyEditors() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        addTab()

        manager.splitActivePaneWithEditor(
            direction: .horizontal,
            theme: testTheme,
            fontFamily: "SF Mono",
            fontSize: 13
        )

        let editorSession = try XCTUnwrap(manager.activeEditorSession)
        editorSession.insertText("unsaved work")

        manager.ghosttyRequestQuit()
        XCTAssertNotNil(manager.pendingCloseConfirmation)
    }

    func testGhosttyCloseWindowBlocksWhenRunningTerminal() throws {
        let settingsStore = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        manager.settingsStore = settingsStore
        manager.blockStore = blockStore
        manager.setConfirmOnCloseRunningSessionEnabled(true)
        addTab()

        let session = try XCTUnwrap(manager.activeSession)
        session.setStatusForTesting(.running)

        manager.ghosttyCloseWindow()
        XCTAssertNotNil(manager.pendingCloseConfirmation)
    }

    // MARK: - Split Direction Fidelity

    func testSplitActivePaneWithSecondPosition() {
        addTab()
        let originalPaneID = manager.activePaneID!
        manager.splitActivePane(
            direction: .horizontal,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )

        guard case .split(_, _, let first, _, _) = manager.activeTab?.rootPane else {
            XCTFail("Expected split root pane")
            return
        }
        // Original pane should be first
        XCTAssertEqual(first.id, originalPaneID)
    }

    func testSplitActivePaneWithFirstPosition() {
        addTab()
        let originalPaneID = manager.activePaneID!
        manager.splitActivePane(
            direction: .horizontal,
            position: .first,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )

        guard case .split(_, _, _, let second, _) = manager.activeTab?.rootPane else {
            XCTFail("Expected split root pane")
            return
        }
        // Original pane should be second when new pane is .first
        XCTAssertEqual(second.id, originalPaneID)
    }

    func testRepeatedSameDirectionSplitsRebalanceSiblingsEvenly() {
        addTab()
        let firstPaneID = manager.activePaneID!

        manager.splitActivePane(
            direction: .horizontal,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let secondPaneID = manager.activePaneID!

        manager.selectPane(id: firstPaneID)
        manager.splitActivePane(
            direction: .horizontal,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let thirdPaneID = manager.activePaneID!

        guard let rootPane = manager.activeTab?.rootPane else {
            XCTFail("Expected active root pane")
            return
        }

        let widths = horizontalWidths(in: rootPane)
        XCTAssertEqual(Double(widths[firstPaneID] ?? 0), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Double(widths[secondPaneID] ?? 0), 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(Double(widths[thirdPaneID] ?? 0), 1.0 / 3.0, accuracy: 0.001)
    }

    func testSelectAdjacentPaneMovesHorizontallyAcrossSplitRow() {
        addTab()
        let firstPaneID = manager.activePaneID!

        manager.splitActivePane(
            direction: .horizontal,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let secondPaneID = manager.activePaneID!

        manager.selectPane(id: firstPaneID)
        manager.selectAdjacentPane(.right)
        XCTAssertEqual(manager.activePaneID, secondPaneID)

        manager.selectAdjacentPane(.left)
        XCTAssertEqual(manager.activePaneID, firstPaneID)
    }

    func testSelectAdjacentPaneMovesVerticallyWithinNestedLayout() {
        addTab()
        let topLeftPaneID = manager.activePaneID!

        manager.splitActivePane(
            direction: .horizontal,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let rightPaneID = manager.activePaneID!

        manager.selectPane(id: topLeftPaneID)
        manager.splitActivePane(
            direction: .vertical,
            position: .second,
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            blockStore: blockStore
        )
        let bottomLeftPaneID = manager.activePaneID!

        manager.selectPane(id: topLeftPaneID)
        manager.selectAdjacentPane(.down)
        XCTAssertEqual(manager.activePaneID, bottomLeftPaneID)

        manager.selectAdjacentPane(.up)
        XCTAssertEqual(manager.activePaneID, topLeftPaneID)

        manager.selectAdjacentPane(.right)
        XCTAssertEqual(manager.activePaneID, rightPaneID)
    }

    private func horizontalWidths(in node: PaneNode, availableWidth: CGFloat = 1) -> [UUID: CGFloat] {
        switch node {
        case .leaf(let id, _):
            return [id: availableWidth]
        case .editor(let id, _):
            return [id: availableWidth]
        case .split(_, let direction, let first, let second, let ratio):
            if direction == .horizontal {
                return horizontalWidths(in: first, availableWidth: availableWidth * ratio)
                    .merging(horizontalWidths(in: second, availableWidth: availableWidth * (1 - ratio))) { _, rhs in rhs }
            }

            return horizontalWidths(in: first, availableWidth: availableWidth)
                .merging(horizontalWidths(in: second, availableWidth: availableWidth)) { _, rhs in rhs }
        }
    }

    private var testTheme: TerminalTheme {
        TerminalTheme(
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
        )
    }
}
