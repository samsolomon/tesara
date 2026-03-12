import XCTest
@testable import Tesara

@MainActor
final class PaneNodeTests: XCTestCase {
    private func makeLeaf() -> PaneNode {
        .leaf(id: UUID(), session: TerminalSession(launcher: MockPaneTestLauncher()))
    }

    // MARK: Leaf Basics

    func testLeafHasCorrectID() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession(launcher: MockPaneTestLauncher()))
        XCTAssertEqual(node.id, id)
    }

    func testLeafSessionIsAccessible() {
        let session = TerminalSession(launcher: MockPaneTestLauncher())
        let node = PaneNode.leaf(id: UUID(), session: session)
        XCTAssertTrue(node.session === session)
    }

    func testSplitSessionIsNil() {
        let node = PaneNode.split(id: UUID(), direction: .horizontal, first: makeLeaf(), second: makeLeaf(), ratio: 0.5)
        XCTAssertNil(node.session)
    }

    // MARK: All Leaf IDs

    func testLeafReturnsOwnID() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession(launcher: MockPaneTestLauncher()))
        XCTAssertEqual(node.allLeafIDs(), [id])
    }

    func testSplitReturnsBothLeafIDs() {
        let id1 = UUID()
        let id2 = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession(launcher: MockPaneTestLauncher())),
            second: .leaf(id: id2, session: TerminalSession(launcher: MockPaneTestLauncher())),
            ratio: 0.5
        )
        XCTAssertEqual(node.allLeafIDs(), [id1, id2])
    }

    // MARK: Find Session

    func testFindSessionInLeaf() {
        let id = UUID()
        let session = TerminalSession(launcher: MockPaneTestLauncher())
        let node = PaneNode.leaf(id: id, session: session)
        XCTAssertTrue(node.findSession(forPaneID: id) === session)
    }

    func testFindSessionInSplit() {
        let id1 = UUID()
        let id2 = UUID()
        let session2 = TerminalSession(launcher: MockPaneTestLauncher())
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession(launcher: MockPaneTestLauncher())),
            second: .leaf(id: id2, session: session2),
            ratio: 0.5
        )
        XCTAssertTrue(node.findSession(forPaneID: id2) === session2)
    }

    func testFindSessionNotFound() {
        let node = makeLeaf()
        XCTAssertNil(node.findSession(forPaneID: UUID()))
    }

    // MARK: Contains

    func testContainsLeafID() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession(launcher: MockPaneTestLauncher()))
        XCTAssertTrue(node.contains(paneID: id))
        XCTAssertFalse(node.contains(paneID: UUID()))
    }

    // MARK: Replace

    func testReplaceLeafWithSplit() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession(launcher: MockPaneTestLauncher()))
        let replacement = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: makeLeaf(), second: makeLeaf(), ratio: 0.5
        )
        let result = node.replacingPane(id: id, with: replacement)
        if case .split = result {
            // success
        } else {
            XCTFail("Expected split node after replacement")
        }
    }

    // MARK: Remove

    func testRemoveOnlyLeafReturnsNil() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession(launcher: MockPaneTestLauncher()))
        XCTAssertNil(node.removingPane(id: id))
    }

    func testRemoveFromSplitPromotesSibling() {
        let id1 = UUID()
        let id2 = UUID()
        let session2 = TerminalSession(launcher: MockPaneTestLauncher())
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession(launcher: MockPaneTestLauncher())),
            second: .leaf(id: id2, session: session2),
            ratio: 0.5
        )
        let result = node.removingPane(id: id1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, id2)
        XCTAssertTrue(result?.session === session2)
    }

    // MARK: Ratio

    func testUpdateRatioClampsToMin() {
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .horizontal,
            first: makeLeaf(), second: makeLeaf(), ratio: 0.5
        )
        let updated = node.updatingRatio(splitID: splitID, ratio: 0.0)
        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.1, accuracy: 0.001)
        } else {
            XCTFail("Expected split")
        }
    }

    func testUpdateRatioClampsToMax() {
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .horizontal,
            first: makeLeaf(), second: makeLeaf(), ratio: 0.5
        )
        let updated = node.updatingRatio(splitID: splitID, ratio: 1.0)
        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.9, accuracy: 0.001)
        } else {
            XCTFail("Expected split")
        }
    }

    func testUpdateRatioValidValue() {
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .horizontal,
            first: makeLeaf(), second: makeLeaf(), ratio: 0.5
        )
        let updated = node.updatingRatio(splitID: splitID, ratio: 0.7)
        if case .split(_, _, _, _, let ratio) = updated {
            XCTAssertEqual(ratio, 0.7, accuracy: 0.001)
        } else {
            XCTFail("Expected split")
        }
    }
}

// Minimal mock launcher for PaneNode tests
private struct MockPaneTestLauncher: TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle {
        MockPaneTestHandle()
    }
}

private struct MockPaneTestHandle: TerminalProcessHandle {
    func send(_ input: String) throws {}
    func resize(cols: UInt16, rows: UInt16) {}
    func stop() {}
}
