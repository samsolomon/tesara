import SwiftUI

struct PaneSplitView<First: View, Second: View>: View {
    let direction: PaneNode.SplitDirection
    let ratio: CGFloat
    let onUpdateRatio: (CGFloat) -> Void
    let first: First
    let second: Second

    private let minSize: CGFloat = 10
    private let visibleDividerSize: CGFloat = 4
    private let hitDividerSize: CGFloat = 18

    init(
        direction: PaneNode.SplitDirection,
        ratio: CGFloat,
        onUpdateRatio: @escaping (CGFloat) -> Void,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.direction = direction
        self.ratio = ratio
        self.onUpdateRatio = onUpdateRatio
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { geo in
            let firstRect = firstRect(for: geo.size)
            let secondRect = secondRect(for: geo.size, firstRect: firstRect)
            let dividerPoint = dividerPoint(for: geo.size, firstRect: firstRect)

            ZStack(alignment: .topLeading) {
                first
                    .frame(width: firstRect.width, height: firstRect.height)
                    .position(x: firstRect.midX, y: firstRect.midY)
                    .clipped()
                second
                    .frame(width: secondRect.width, height: secondRect.height)
                    .position(x: secondRect.midX, y: secondRect.midY)
                    .clipped()
                PaneDividerView(
                    direction: direction,
                    visibleSize: visibleDividerSize,
                    hitSize: hitDividerSize
                )
                .position(dividerPoint)
                .zIndex(10)
                PaneDividerInteractionOverlay(
                    direction: direction,
                    ratio: ratio,
                    minSize: minSize,
                    hitSize: hitDividerSize,
                    onUpdateRatio: onUpdateRatio
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .zIndex(20)
            }
        }
    }

    private func firstRect(for size: CGSize) -> CGRect {
        var rect = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            rect.size.width *= ratio
            rect.size.width -= visibleDividerSize / 2
        case .vertical:
            rect.size.height *= ratio
            rect.size.height -= visibleDividerSize / 2
        }
        return rect
    }

    private func secondRect(for size: CGSize, firstRect: CGRect) -> CGRect {
        var rect = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            rect.origin.x = firstRect.width + visibleDividerSize / 2
            rect.size.width -= rect.origin.x
        case .vertical:
            rect.origin.y = firstRect.height + visibleDividerSize / 2
            rect.size.height -= rect.origin.y
        }
        return rect
    }

    private func dividerPoint(for size: CGSize, firstRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            return CGPoint(x: firstRect.width, y: size.height / 2)
        case .vertical:
            return CGPoint(x: size.width / 2, y: firstRect.height)
        }
    }
}

struct PaneDividerView: View {
    let direction: PaneNode.SplitDirection
    let visibleSize: CGFloat
    let hitSize: CGFloat

    private var visibleWidth: CGFloat? {
        direction == .horizontal ? visibleSize : nil
    }

    private var visibleHeight: CGFloat? {
        direction == .vertical ? visibleSize : nil
    }

    private var hitWidth: CGFloat? {
        direction == .horizontal ? hitSize : nil
    }

    private var hitHeight: CGFloat? {
        direction == .vertical ? hitSize : nil
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: hitWidth, height: hitHeight)
                .contentShape(Rectangle())
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: visibleWidth, height: visibleHeight)
        }
    }
}

private struct PaneDividerInteractionOverlay: NSViewRepresentable {
    let direction: PaneNode.SplitDirection
    let ratio: CGFloat
    let minSize: CGFloat
    let hitSize: CGFloat
    let onUpdateRatio: (CGFloat) -> Void

    func makeNSView(context: Context) -> PaneDividerInteractionNSView {
        let view = PaneDividerInteractionNSView()
        view.update(
            direction: direction,
            ratio: ratio,
            minSize: minSize,
            hitSize: hitSize,
            onUpdateRatio: onUpdateRatio
        )
        return view
    }

    func updateNSView(_ nsView: PaneDividerInteractionNSView, context: Context) {
        nsView.update(
            direction: direction,
            ratio: ratio,
            minSize: minSize,
            hitSize: hitSize,
            onUpdateRatio: onUpdateRatio
        )
    }
}

private final class PaneDividerInteractionNSView: NSView {
    private var direction: PaneNode.SplitDirection = .horizontal
    private var ratio: CGFloat = 0.5
    private var minSize: CGFloat = 10
    private var hitSize: CGFloat = 18
    private var onUpdateRatio: ((CGFloat) -> Void)?

    override var isFlipped: Bool { true }

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
        dividerHitRect().contains(point) ? self : nil
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
        addCursorRect(dividerHitRect(), cursor: cursor)
    }

    func update(
        direction: PaneNode.SplitDirection,
        ratio: CGFloat,
        minSize: CGFloat,
        hitSize: CGFloat,
        onUpdateRatio: @escaping (CGFloat) -> Void
    ) {
        self.direction = direction
        self.ratio = ratio
        self.minSize = minSize
        self.hitSize = hitSize
        self.onUpdateRatio = onUpdateRatio
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        #if DEBUG
        LocalLogStore.shared.log(
            "[DividerDrag] began ratio=\(String(format: "%.4f", Double(ratio))) size=\(Int(bounds.width))x\(Int(bounds.height))"
        )
        #endif

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: .greatestFiniteMagnitude,
            mode: .eventTracking
        ) { [weak self] trackedEvent, stop in
            guard let self, let trackedEvent else { return }

            switch trackedEvent.type {
            case .leftMouseDragged:
                let point = self.convert(trackedEvent.locationInWindow, from: nil)
                let newRatio = self.ratio(for: point)
                #if DEBUG
                LocalLogStore.shared.log(
                    "[DividerDrag] point=\(Int(point.x))x\(Int(point.y)) ratio=\(String(format: "%.4f", Double(newRatio)))"
                )
                #endif
                self.onUpdateRatio?(newRatio)

            case .leftMouseUp:
                #if DEBUG
                LocalLogStore.shared.log("[DividerDrag] ended")
                #endif
                stop.pointee = true

            default:
                break
            }
        }
    }

    private func dividerHitRect() -> CGRect {
        switch direction {
        case .horizontal:
            let centerX = bounds.width * ratio
            return CGRect(
                x: centerX - hitSize / 2,
                y: 0,
                width: hitSize,
                height: bounds.height
            )
        case .vertical:
            let centerY = bounds.height * ratio
            return CGRect(
                x: 0,
                y: centerY - hitSize / 2,
                width: bounds.width,
                height: hitSize
            )
        }
    }

    private func ratio(for point: CGPoint) -> CGFloat {
        switch direction {
        case .horizontal:
            let width = max(bounds.width, 1)
            let position = min(max(minSize, point.x), width - minSize)
            return position / width
        case .vertical:
            let height = max(bounds.height, 1)
            let position = min(max(minSize, point.y), height - minSize)
            return position / height
        }
    }
}
