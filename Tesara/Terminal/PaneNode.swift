import Foundation

indirect enum PaneNode: Identifiable {
    case leaf(id: UUID, session: TerminalSession)
    case editor(id: UUID, session: EditorSession)
    case split(id: UUID, direction: SplitDirection, first: PaneNode, second: PaneNode, ratio: CGFloat)

    enum SplitDirection {
        case horizontal
        case vertical
    }

    /// Whether the new pane goes before or after the existing one in a split.
    enum PanePosition {
        case first
        case second
    }

    enum NavigationDirection {
        case left
        case right
        case up
        case down
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

    func insertingPane(
        id targetID: UUID,
        newPane: PaneNode,
        direction: SplitDirection,
        position: PanePosition
    ) -> PaneNode {
        switch self {
        case .leaf(let id, _):
            guard id == targetID else { return self }
            return Self.makeSplit(
                direction: direction,
                first: position == .second ? self : newPane,
                second: position == .second ? newPane : self,
                ratio: 0.5
            )

        case .editor(let id, _):
            guard id == targetID else { return self }
            return Self.makeSplit(
                direction: direction,
                first: position == .second ? self : newPane,
                second: position == .second ? newPane : self,
                ratio: 0.5
            )

        case .split(let id, let splitDirection, let first, let second, let ratio):
            if splitDirection == direction {
                let firstParticipates = first.participatesInSameDirectionInsertion(targetID: targetID, direction: direction)
                let secondParticipates = second.participatesInSameDirectionInsertion(targetID: targetID, direction: direction)

                if firstParticipates || secondParticipates {
                    var siblings = flattenedSiblings(for: direction)
                    guard let targetIndex = siblings.firstIndex(where: { $0.contains(paneID: targetID) }) else {
                        return self
                    }
                    let insertionIndex = position == .first ? targetIndex : targetIndex + 1
                    siblings.insert(newPane, at: insertionIndex)
                    return Self.rebuildEvenly(siblings, direction: direction)
                }
            }

            return .split(
                id: id,
                direction: splitDirection,
                first: first.insertingPane(id: targetID, newPane: newPane, direction: direction, position: position),
                second: second.insertingPane(id: targetID, newPane: newPane, direction: direction, position: position),
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
            let newFirst: PaneNode? = first.contains(paneID: targetID) ? first.removingPane(id: targetID) : first
            let newSecond: PaneNode? = second.contains(paneID: targetID) ? second.removingPane(id: targetID) : second

            switch (newFirst, newSecond) {
            case (nil, nil):
                return nil
            case (nil, let remainingSecond?):
                return remainingSecond
            case (let remainingFirst?, nil):
                return remainingFirst
            case (let remainingFirst?, let remainingSecond?):
                return .split(
                    id: id,
                    direction: direction,
                    first: remainingFirst,
                    second: remainingSecond,
                    ratio: ratio
                )
            }
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
        let clamped = min(max(ratio, 0.05), 0.95)
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

    func adjacentPaneID(to paneID: UUID, direction: NavigationDirection) -> UUID? {
        let frames = leafFrames(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let current = frames.first(where: { $0.id == paneID }) else { return nil }

        let candidates = frames
            .filter { $0.id != paneID }
            .compactMap { candidate -> (id: UUID, primary: CGFloat, secondary: CGFloat, overlap: CGFloat)? in
                switch direction {
                case .left:
                    let primary = current.frame.minX - candidate.frame.maxX
                    let overlap = overlapLength(current.frame.minY...current.frame.maxY, candidate.frame.minY...candidate.frame.maxY)
                    guard primary >= -0.0001, overlap > 0 else { return nil }
                    let secondary = abs(candidate.frame.midY - current.frame.midY)
                    return (candidate.id, primary, secondary, overlap)

                case .right:
                    let primary = candidate.frame.minX - current.frame.maxX
                    let overlap = overlapLength(current.frame.minY...current.frame.maxY, candidate.frame.minY...candidate.frame.maxY)
                    guard primary >= -0.0001, overlap > 0 else { return nil }
                    let secondary = abs(candidate.frame.midY - current.frame.midY)
                    return (candidate.id, primary, secondary, overlap)

                case .up:
                    let primary = current.frame.minY - candidate.frame.maxY
                    let overlap = overlapLength(current.frame.minX...current.frame.maxX, candidate.frame.minX...candidate.frame.maxX)
                    guard primary >= -0.0001, overlap > 0 else { return nil }
                    let secondary = abs(candidate.frame.midX - current.frame.midX)
                    return (candidate.id, primary, secondary, overlap)

                case .down:
                    let primary = candidate.frame.minY - current.frame.maxY
                    let overlap = overlapLength(current.frame.minX...current.frame.maxX, candidate.frame.minX...candidate.frame.maxX)
                    guard primary >= -0.0001, overlap > 0 else { return nil }
                    let secondary = abs(candidate.frame.midX - current.frame.midX)
                    return (candidate.id, primary, secondary, overlap)
                }
            }

        return candidates.min {
            if abs($0.primary - $1.primary) > 0.0001 {
                return $0.primary < $1.primary
            }
            if abs($0.secondary - $1.secondary) > 0.0001 {
                return $0.secondary < $1.secondary
            }
            return $0.overlap > $1.overlap
        }?.id
    }

    private func participatesInSameDirectionInsertion(targetID: UUID, direction: SplitDirection) -> Bool {
        switch self {
        case .leaf(let id, _):
            return id == targetID
        case .editor(let id, _):
            return id == targetID
        case .split(_, let splitDirection, _, _, _):
            return splitDirection == direction && contains(paneID: targetID)
        }
    }

    private func flattenedSiblings(for direction: SplitDirection) -> [PaneNode] {
        switch self {
        case .split(_, let splitDirection, let first, let second, _) where splitDirection == direction:
            return first.flattenedSiblings(for: direction) + second.flattenedSiblings(for: direction)
        default:
            return [self]
        }
    }

    private static func rebuildEvenly(_ siblings: [PaneNode], direction: SplitDirection) -> PaneNode {
        guard siblings.count > 1 else {
            return siblings[0]
        }

        let first = siblings[0]
        let remaining = Array(siblings.dropFirst())
        return makeSplit(
            direction: direction,
            first: first,
            second: rebuildEvenly(remaining, direction: direction),
            ratio: 1 / CGFloat(siblings.count)
        )
    }

    private static func makeSplit(
        direction: SplitDirection,
        first: PaneNode,
        second: PaneNode,
        ratio: CGFloat
    ) -> PaneNode {
        .split(id: UUID(), direction: direction, first: first, second: second, ratio: ratio)
    }

    private func leafFrames(in rect: CGRect) -> [(id: UUID, frame: CGRect)] {
        switch self {
        case .leaf(let id, _):
            return [(id, rect)]
        case .editor(let id, _):
            return [(id, rect)]
        case .split(_, let direction, let first, let second, let ratio):
            switch direction {
            case .horizontal:
                let firstWidth = rect.width * ratio
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
                let secondRect = CGRect(x: rect.minX + firstWidth, y: rect.minY, width: rect.width - firstWidth, height: rect.height)
                return first.leafFrames(in: firstRect) + second.leafFrames(in: secondRect)
            case .vertical:
                let firstHeight = rect.height * ratio
                let firstRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
                let secondRect = CGRect(x: rect.minX, y: rect.minY + firstHeight, width: rect.width, height: rect.height - firstHeight)
                return first.leafFrames(in: firstRect) + second.leafFrames(in: secondRect)
            }
        }
    }

    private func overlapLength(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }
}
