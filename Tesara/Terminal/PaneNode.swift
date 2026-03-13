import Foundation

indirect enum PaneNode: Identifiable {
    case leaf(id: UUID, session: TerminalSession)
    case editor(id: UUID, session: EditorSession)
    case split(id: UUID, direction: SplitDirection, first: PaneNode, second: PaneNode, ratio: CGFloat)

    enum SplitDirection {
        case horizontal
        case vertical
    }

    var id: UUID {
        switch self {
        case .leaf(let id, _): return id
        case .editor(let id, _): return id
        case .split(let id, _, _, _, _): return id
        }
    }

    var session: TerminalSession? {
        switch self {
        case .leaf(_, let session): return session
        case .editor: return nil
        case .split: return nil
        }
    }

    var editorSession: EditorSession? {
        switch self {
        case .leaf: return nil
        case .editor(_, let session): return session
        case .split: return nil
        }
    }

    func findSession(forPaneID paneID: UUID) -> TerminalSession? {
        switch self {
        case .leaf(let id, let session):
            return id == paneID ? session : nil
        case .editor:
            return nil
        case .split(_, _, let first, let second, _):
            return first.findSession(forPaneID: paneID) ?? second.findSession(forPaneID: paneID)
        }
    }

    func findEditorSession(forPaneID paneID: UUID) -> EditorSession? {
        switch self {
        case .leaf:
            return nil
        case .editor(let id, let session):
            return id == paneID ? session : nil
        case .split(_, _, let first, let second, _):
            return first.findEditorSession(forPaneID: paneID) ?? second.findEditorSession(forPaneID: paneID)
        }
    }

    func allLeafIDs() -> [UUID] {
        switch self {
        case .leaf(let id, _):
            return [id]
        case .editor(let id, _):
            return [id]
        case .split(_, _, let first, let second, _):
            return first.allLeafIDs() + second.allLeafIDs()
        }
    }

    func contains(paneID: UUID) -> Bool {
        switch self {
        case .leaf(let id, _):
            return id == paneID
        case .editor(let id, _):
            return id == paneID
        case .split(let id, _, let first, let second, _):
            return id == paneID || first.contains(paneID: paneID) || second.contains(paneID: paneID)
        }
    }

    func replacingPane(id targetID: UUID, with newNode: PaneNode) -> PaneNode {
        switch self {
        case .leaf(let id, _):
            return id == targetID ? newNode : self
        case .editor(let id, _):
            return id == targetID ? newNode : self
        case .split(let id, let direction, let first, let second, let ratio):
            return .split(
                id: id,
                direction: direction,
                first: first.replacingPane(id: targetID, with: newNode),
                second: second.replacingPane(id: targetID, with: newNode),
                ratio: ratio
            )
        }
    }

    func removingPane(id targetID: UUID) -> PaneNode? {
        switch self {
        case .leaf(let id, _):
            return id == targetID ? nil : self
        case .editor(let id, _):
            return id == targetID ? nil : self
        case .split(let id, let direction, let first, let second, let ratio):
            if first.id == targetID || (first.contains(paneID: targetID) && first.removingPane(id: targetID) == nil) {
                return second
            }
            if second.id == targetID || (second.contains(paneID: targetID) && second.removingPane(id: targetID) == nil) {
                return first
            }
            if let newFirst = first.removingPane(id: targetID) {
                return .split(id: id, direction: direction, first: newFirst, second: second, ratio: ratio)
            }
            if let newSecond = second.removingPane(id: targetID) {
                return .split(id: id, direction: direction, first: first, second: newSecond, ratio: ratio)
            }
            return self
        }
    }

    func allEditorSessions() -> [(paneID: UUID, session: EditorSession)] {
        switch self {
        case .leaf:
            return []
        case .editor(let id, let session):
            return [(id, session)]
        case .split(_, _, let first, let second, _):
            return first.allEditorSessions() + second.allEditorSessions()
        }
    }

    func allTerminalSessions() -> [(paneID: UUID, session: TerminalSession)] {
        switch self {
        case .leaf(let id, let session):
            return [(id, session)]
        case .editor:
            return []
        case .split(_, _, let first, let second, _):
            return first.allTerminalSessions() + second.allTerminalSessions()
        }
    }

    func updatingRatio(splitID: UUID, ratio: CGFloat) -> PaneNode {
        let clamped = min(max(ratio, 0.1), 0.9)
        switch self {
        case .leaf:
            return self
        case .editor:
            return self
        case .split(let id, let direction, let first, let second, let currentRatio):
            if id == splitID {
                return .split(id: id, direction: direction, first: first, second: second, ratio: clamped)
            }
            return .split(
                id: id,
                direction: direction,
                first: first.updatingRatio(splitID: splitID, ratio: ratio),
                second: second.updatingRatio(splitID: splitID, ratio: ratio),
                ratio: currentRatio
            )
        }
    }
}
