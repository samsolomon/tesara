import AppKit
import Sparkle
import SwiftUI

@MainActor
final class SettingsPaneSelection: ObservableObject {
    private static let defaultsKey = "settings.selectedPane"

    @Published var pane: SettingsPane {
        didSet {
            UserDefaults.standard.set(pane.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? SettingsPane.appearance.rawValue
        self.pane = SettingsPane(rawValue: raw) ?? .appearance
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    let paneSelection = SettingsPaneSelection()

    private var settingsStore: SettingsStore?
    private var blockStore: BlockStore?
    private var updater: SPUUpdater?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 840, height: 560))
        window.minSize = NSSize(width: 840, height: 560)
        window.maxSize = NSSize(width: 840, height: 560)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(settingsStore: SettingsStore, blockStore: BlockStore, updater: SPUUpdater) {
        self.settingsStore = settingsStore
        self.blockStore = blockStore
        self.updater = updater
    }

    override func showWindow(_ sender: Any?) {
        guard let settingsStore, let blockStore, let updater else { return }

        if window?.contentViewController == nil {
            let splitVC = TrafficLightOffsetSplitViewController()

            let sidebarView = SettingsSidebarView(paneSelection: paneSelection)
            let sidebarHosting = NSHostingController(rootView: sidebarView)
            sidebarHosting.sizingOptions = []
            let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
            sidebarItem.canCollapse = false
            sidebarItem.minimumThickness = 248
            sidebarItem.maximumThickness = 248

            let detailView = SettingsDetailView(paneSelection: paneSelection, updater: updater)
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
            let detailHosting = NSHostingController(rootView: detailView)
            detailHosting.sizingOptions = []
            let detailItem = NSSplitViewItem(viewController: detailHosting)

            splitVC.addSplitViewItem(sidebarItem)
            splitVC.addSplitViewItem(detailItem)
            splitVC.preferredContentSize = NSSize(width: 840, height: 560)

            window?.contentViewController = splitVC
        }

        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
    }
}

private final class TrafficLightOffsetSplitViewController: NSSplitViewController {
    private static let offset: CGFloat = 8
    private var defaultButtonY: CGFloat?

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let window = view.window,
              let close = window.standardWindowButton(.closeButton) else { return }

        if defaultButtonY == nil {
            defaultButtonY = close.frame.origin.y
        }
        guard let defaultY = defaultButtonY else { return }

        let isFlipped = close.superview?.isFlipped ?? false
        let targetY = isFlipped ? defaultY + Self.offset : defaultY - Self.offset

        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            if abs(button.frame.origin.y - targetY) > 0.5 {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: targetY))
            }
        }
    }
}
