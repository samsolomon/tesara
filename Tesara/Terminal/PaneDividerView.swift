import SwiftUI

struct PaneDividerView: View {
    let direction: PaneNode.SplitDirection

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(
                width: direction == .horizontal ? 4 : nil,
                height: direction == .vertical ? 4 : nil
            )
    }
}

struct PaneDividerDragOverlay: NSViewRepresentable {
    let direction: PaneNode.SplitDirection
    let initialRatio: CGFloat
    let totalSize: CGFloat
    let onUpdateRatio: (CGFloat) -> Void

    func makeNSView(context: Context) -> PaneDividerDragNSView {
        let view = PaneDividerDragNSView()
        view.update(
            direction: direction,
            initialRatio: initialRatio,
            totalSize: totalSize,
            onUpdateRatio: onUpdateRatio
        )
        return view
    }

    func updateNSView(_ nsView: PaneDividerDragNSView, context: Context) {
        nsView.update(
            direction: direction,
            initialRatio: initialRatio,
            totalSize: totalSize,
            onUpdateRatio: onUpdateRatio
        )
    }
}

final class PaneDividerDragNSView: NSView {
    private var direction: PaneNode.SplitDirection = .horizontal
    private var initialRatio: CGFloat = 0.5
    private var totalSize: CGFloat = 1
    private var onUpdateRatio: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor = switch direction {
        case .horizontal: .resizeLeftRight
        case .vertical: .resizeUpDown
        }
        addCursorRect(bounds, cursor: cursor)
    }

    func update(
        direction: PaneNode.SplitDirection,
        initialRatio: CGFloat,
        totalSize: CGFloat,
        onUpdateRatio: @escaping (CGFloat) -> Void
    ) {
        self.direction = direction
        self.initialRatio = initialRatio
        self.totalSize = max(totalSize, 1)
        self.onUpdateRatio = onUpdateRatio
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        let startPoint = convert(event.locationInWindow, from: nil)
        let startLocation = direction == .horizontal ? startPoint.x : startPoint.y
        LocalLogStore.shared.log(
            "[DividerDrag] began initialRatio=\(String(format: "%.4f", Double(initialRatio))) totalSize=\(Int(totalSize))"
        )

        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .greatestFiniteMagnitude, mode: .eventTracking) { [weak self] trackedEvent, stop in
            guard let self else { return }
            guard let trackedEvent else { return }

            switch trackedEvent.type {
            case .leftMouseDragged:
                let point = self.convert(trackedEvent.locationInWindow, from: nil)
                let currentLocation = self.direction == .horizontal ? point.x : point.y
                let delta = currentLocation - startLocation
                let newRatio = self.initialRatio + delta / self.totalSize
                LocalLogStore.shared.log(
                    "[DividerDrag] delta=\(String(format: "%.2f", Double(delta))) newRatio=\(String(format: "%.4f", Double(newRatio)))"
                )
                self.onUpdateRatio?(newRatio)

            case .leftMouseUp:
                LocalLogStore.shared.log("[DividerDrag] ended")
                stop.pointee = true

            default:
                break
            }
        }
    }
}
