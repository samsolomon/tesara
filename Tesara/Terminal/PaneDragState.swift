import SwiftUI

@MainActor
final class PaneDragState: ObservableObject {
    @Published var activeDragSourceID: UUID?
    private(set) var previewSnapshot: PaneNode?

    var swapHandler: ((UUID, UUID) -> Void)?
    var snapshotProvider: (() -> PaneNode?)?
    var restoreHandler: ((PaneNode) -> Void)?
    private var cleanupTask: Task<Void, Never>?

    func dragStarted(sourceID: UUID) {
        guard activeDragSourceID != sourceID else { return }
        cleanupTask?.cancel()
        previewSnapshot = snapshotProvider?()
        activeDragSourceID = sourceID
    }

    func targetEntered(_ paneID: UUID) {
        cleanupTask?.cancel()
        guard let sourceID = activeDragSourceID, paneID != sourceID else { return }
        swapHandler?(sourceID, paneID)
    }

    func targetExited(_ paneID: UUID) {
        cleanupTask?.cancel()
        cleanupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            cancelDrag()
        }
    }

    func dropPerformed() {
        cleanupTask?.cancel()
        previewSnapshot = nil
        activeDragSourceID = nil
    }

    func cancelDrag() {
        cleanupTask?.cancel()
        if let snapshot = previewSnapshot {
            restoreHandler?(snapshot)
        }
        previewSnapshot = nil
        activeDragSourceID = nil
    }
}
