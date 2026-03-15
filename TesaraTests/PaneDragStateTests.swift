import XCTest
@testable import Tesara

@MainActor
final class PaneDragStateTests: XCTestCase {

    private var state: PaneDragState!

    override func setUp() {
        super.setUp()
        state = PaneDragState()
    }

    // MARK: - Initial State

    func testInitialStateHasNoActiveDrag() {
        XCTAssertNil(state.activeDragSourceID)
        XCTAssertNil(state.previewSnapshot)
    }

    // MARK: - Drag Started

    func testDragStartedSetsSourceID() {
        let id = UUID()
        state.dragStarted(sourceID: id)
        XCTAssertEqual(state.activeDragSourceID, id)
    }

    func testDragStartedCapturesSnapshot() {
        let snapshotNode = PaneNode.leaf(id: UUID(), session: TerminalSession())
        state.snapshotProvider = { snapshotNode }

        state.dragStarted(sourceID: UUID())
        XCTAssertNotNil(state.previewSnapshot)
    }

    func testDragStartedWithNilSnapshotProvider() {
        state.snapshotProvider = nil
        state.dragStarted(sourceID: UUID())
        XCTAssertNil(state.previewSnapshot)
    }

    func testDragStartedIdempotentForSameID() {
        let id = UUID()
        var snapshotCallCount = 0
        state.snapshotProvider = {
            snapshotCallCount += 1
            return PaneNode.leaf(id: UUID(), session: TerminalSession())
        }

        state.dragStarted(sourceID: id)
        XCTAssertEqual(snapshotCallCount, 1)

        state.dragStarted(sourceID: id)
        // Guard prevents re-capture for same ID
        XCTAssertEqual(snapshotCallCount, 1)
    }

    func testDragStartedWithDifferentIDReplacesSource() {
        let first = UUID()
        let second = UUID()
        state.snapshotProvider = { PaneNode.leaf(id: UUID(), session: TerminalSession()) }

        state.dragStarted(sourceID: first)
        XCTAssertEqual(state.activeDragSourceID, first)

        state.dragStarted(sourceID: second)
        XCTAssertEqual(state.activeDragSourceID, second)
    }

    // MARK: - Target Entered

    func testTargetEnteredCallsSwapHandler() {
        let sourceID = UUID()
        let targetID = UUID()
        var swapCalled: (UUID, UUID)?
        state.swapHandler = { swapCalled = ($0, $1) }

        state.dragStarted(sourceID: sourceID)
        state.targetEntered(targetID)

        XCTAssertEqual(swapCalled?.0, sourceID)
        XCTAssertEqual(swapCalled?.1, targetID)
    }

    func testTargetEnteredWithSameIDAsSourceDoesNotSwap() {
        let sourceID = UUID()
        var swapCalled = false
        state.swapHandler = { _, _ in swapCalled = true }

        state.dragStarted(sourceID: sourceID)
        state.targetEntered(sourceID)

        XCTAssertFalse(swapCalled)
    }

    func testTargetEnteredWithoutDragDoesNotSwap() {
        var swapCalled = false
        state.swapHandler = { _, _ in swapCalled = true }

        state.targetEntered(UUID())

        XCTAssertFalse(swapCalled)
    }

    // MARK: - Drop Performed

    func testDropPerformedClearsState() {
        let id = UUID()
        state.snapshotProvider = { PaneNode.leaf(id: UUID(), session: TerminalSession()) }
        state.dragStarted(sourceID: id)

        state.dropPerformed()

        XCTAssertNil(state.activeDragSourceID)
        XCTAssertNil(state.previewSnapshot)
    }

    // MARK: - Cancel Drag

    func testCancelDragRestoresSnapshot() {
        let snapshotNode = PaneNode.leaf(id: UUID(), session: TerminalSession())
        state.snapshotProvider = { snapshotNode }
        var restoredNode: PaneNode?
        state.restoreHandler = { restoredNode = $0 }

        state.dragStarted(sourceID: UUID())
        state.cancelDrag()

        XCTAssertNotNil(restoredNode)
        XCTAssertNil(state.activeDragSourceID)
        XCTAssertNil(state.previewSnapshot)
    }

    func testCancelDragWithoutSnapshotDoesNotCallRestore() {
        var restoreCalled = false
        state.restoreHandler = { _ in restoreCalled = true }
        state.snapshotProvider = { nil }

        state.dragStarted(sourceID: UUID())
        state.cancelDrag()

        XCTAssertFalse(restoreCalled)
    }

    func testCancelDragClearsState() {
        state.snapshotProvider = { PaneNode.leaf(id: UUID(), session: TerminalSession()) }
        state.restoreHandler = { _ in }

        state.dragStarted(sourceID: UUID())
        state.cancelDrag()

        XCTAssertNil(state.activeDragSourceID)
        XCTAssertNil(state.previewSnapshot)
    }

    // MARK: - Target Exited Cleanup

    func testTargetExitedSchedulesCleanupThatRestoresSnapshot() async throws {
        let snapshotNode = PaneNode.leaf(id: UUID(), session: TerminalSession())
        state.snapshotProvider = { snapshotNode }
        var restored = false
        state.restoreHandler = { _ in restored = true }

        state.dragStarted(sourceID: UUID())
        state.targetExited(UUID())

        // Wait for the 300ms cleanup task + buffer
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(restored)
        XCTAssertNil(state.activeDragSourceID)
    }

    func testTargetEnteredCancelsCleanupTask() async throws {
        let sourceID = UUID()
        let targetID = UUID()
        state.snapshotProvider = { PaneNode.leaf(id: UUID(), session: TerminalSession()) }
        var restored = false
        state.restoreHandler = { _ in restored = true }
        state.swapHandler = { _, _ in }

        state.dragStarted(sourceID: sourceID)
        state.targetExited(UUID())
        // Immediately re-enter before cleanup fires
        state.targetEntered(targetID)

        try await Task.sleep(for: .milliseconds(500))

        // Cleanup should have been cancelled — no restore
        XCTAssertFalse(restored)
        XCTAssertNotNil(state.activeDragSourceID)
    }

    func testDropPerformedCancelsCleanupTask() async throws {
        state.snapshotProvider = { PaneNode.leaf(id: UUID(), session: TerminalSession()) }
        var restored = false
        state.restoreHandler = { _ in restored = true }

        state.dragStarted(sourceID: UUID())
        state.targetExited(UUID())
        state.dropPerformed()

        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(restored)
        XCTAssertNil(state.activeDragSourceID)
    }
}
