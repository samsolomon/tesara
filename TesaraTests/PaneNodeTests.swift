import XCTest
@testable import Tesara

@MainActor
final class PaneNodeTests: XCTestCase {
    private func makeLeaf() -> PaneNode {
        .leaf(id: UUID(), session: TerminalSession())
    }

    // MARK: Leaf Basics

    func testLeafHasCorrectID() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession())
        XCTAssertEqual(node.id, id)
    }

    func testLeafSessionIsAccessible() {
        let session = TerminalSession()
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
        let node = PaneNode.leaf(id: id, session: TerminalSession())
        XCTAssertEqual(node.allLeafIDs(), [id])
    }

    func testSplitReturnsBothLeafIDs() {
        let id1 = UUID()
        let id2 = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession()),
            second: .leaf(id: id2, session: TerminalSession()),
            ratio: 0.5
        )
        XCTAssertEqual(node.allLeafIDs(), [id1, id2])
    }

    // MARK: Find Session

    func testFindSessionInLeaf() {
        let id = UUID()
        let session = TerminalSession()
        let node = PaneNode.leaf(id: id, session: session)
        XCTAssertTrue(node.findSession(forPaneID: id) === session)
    }

    func testFindSessionInSplit() {
        let id1 = UUID()
        let id2 = UUID()
        let session2 = TerminalSession()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession()),
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
        let node = PaneNode.leaf(id: id, session: TerminalSession())
        XCTAssertTrue(node.contains(paneID: id))
        XCTAssertFalse(node.contains(paneID: UUID()))
    }

    // MARK: Replace

    func testReplaceLeafWithSplit() {
        let id = UUID()
        let node = PaneNode.leaf(id: id, session: TerminalSession())
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
        let node = PaneNode.leaf(id: id, session: TerminalSession())
        XCTAssertNil(node.removingPane(id: id))
    }

    func testRemoveFromSplitPromotesSibling() {
        let id1 = UUID()
        let id2 = UUID()
        let session2 = TerminalSession()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: id1, session: TerminalSession()),
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

    // MARK: - Editor Pane

    private func makeEditor() -> PaneNode {
        .editor(id: UUID(), session: EditorSession())
    }

    func testEditorHasCorrectID() {
        let id = UUID()
        let node = PaneNode.editor(id: id, session: EditorSession())
        XCTAssertEqual(node.id, id)
    }

    func testEditorSessionIsNilForTerminal() {
        let node = PaneNode.editor(id: UUID(), session: EditorSession())
        XCTAssertNil(node.session) // .session returns TerminalSession?
    }

    func testEditorSessionIsAccessible() {
        let editorSession = EditorSession()
        let node = PaneNode.editor(id: UUID(), session: editorSession)
        XCTAssertTrue(node.editorSession === editorSession)
    }

    func testFindEditorSessionInSplit() {
        let editorID = UUID()
        let editorSession = EditorSession()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: makeLeaf(),
            second: .editor(id: editorID, session: editorSession),
            ratio: 0.5
        )
        XCTAssertTrue(node.findEditorSession(forPaneID: editorID) === editorSession)
        XCTAssertNil(node.findSession(forPaneID: editorID))
    }

    func testEditorIncludedInAllLeafIDs() {
        let editorID = UUID()
        let leafID = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: leafID, session: TerminalSession()),
            second: .editor(id: editorID, session: EditorSession()),
            ratio: 0.5
        )
        let ids = node.allLeafIDs()
        XCTAssertEqual(ids, [leafID, editorID])
    }

    func testRemoveEditorPromotesTerminal() {
        let leafID = UUID()
        let editorID = UUID()
        let termSession = TerminalSession()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal,
            first: .leaf(id: leafID, session: termSession),
            second: .editor(id: editorID, session: EditorSession()),
            ratio: 0.5
        )
        let result = node.removingPane(id: editorID)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.id, leafID)
        XCTAssertTrue(result?.session === termSession)
    }

    func testContainsEditorID() {
        let editorID = UUID()
        let node = PaneNode.editor(id: editorID, session: EditorSession())
        XCTAssertTrue(node.contains(paneID: editorID))
        XCTAssertFalse(node.contains(paneID: UUID()))
    }

    func testReplaceEditorWithLeaf() {
        let editorID = UUID()
        let node = PaneNode.editor(id: editorID, session: EditorSession())
        let replacement = makeLeaf()
        let result = node.replacingPane(id: editorID, with: replacement)
        XCTAssertNotNil(result.session)
    }
}
