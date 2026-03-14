import AppKit
import Combine
import Carbon

/// Intercepts key events via a local event monitor and dispatches matching
/// key binding overrides to the appropriate app action.
@MainActor
final class KeyBindingDispatcher: ObservableObject {
    private var eventMonitor: Any?
    private var cancellable: AnyCancellable?
    private var lookupTable: [KeyCombo: KeyBindingAction] = [:]

    private weak var settingsStore: SettingsStore?
    private weak var workspaceManager: WorkspaceManager?
    private weak var blockStore: BlockStore?
    private weak var settingsOpenCoordinator: SettingsOpenCoordinator?

    struct KeyCombo: Hashable {
        let key: String
        let modifiers: NSEvent.ModifierFlags

        func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(modifiers.rawValue)
        }

        static func == (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
            lhs.key == rhs.key && lhs.modifiers == rhs.modifiers
        }
    }

    func configure(
        settingsStore: SettingsStore,
        workspaceManager: WorkspaceManager,
        blockStore: BlockStore,
        settingsOpenCoordinator: SettingsOpenCoordinator
    ) {
        self.settingsStore = settingsStore
        self.workspaceManager = workspaceManager
        self.blockStore = blockStore
        self.settingsOpenCoordinator = settingsOpenCoordinator

        rebuildLookupTable()

        if cancellable == nil {
            cancellable = settingsStore.$settings
                .map(\.keyBindingOverrides)
                .removeDuplicates()
                .sink { [weak self] _ in
                    self?.rebuildLookupTable()
                }
        }

        if eventMonitor == nil {
            installMonitor()
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: - Lookup Table

    private func rebuildLookupTable() {
        guard let settingsStore else { return }

        var table: [KeyCombo: KeyBindingAction] = [:]
        for override in settingsStore.settings.keyBindingOverrides {
            let combo = KeyCombo(
                key: override.shortcut.key,
                modifiers: override.shortcut.eventModifierFlags
            )
            table[combo] = override.action
        }
        lookupTable = table
    }

    // MARK: - Event Monitor

    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // AppKit guarantees main-thread delivery, but the closure type is not @MainActor
            return MainActor.assumeIsolated {
                self.handleKeyEvent(event)
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if ShortcutRecordingState.isRecording {
            return event
        }

        if isOpenSettingsShortcut(event) {
            settingsOpenCoordinator?.openSettings()
            return nil
        }

        if let direction = paneNavigationDirection(for: event),
           let responder = event.window?.firstResponder,
           (responder is GhosttySurfaceView || responder is EditorView),
           workspaceManager?.selectAdjacentPane(direction) == true {
            return nil
        }

        // Don't intercept events in text-input contexts (text fields, editor view, key recorder)
        if let responder = event.window?.firstResponder,
           responder is NSTextView || responder is NSTextField || responder is EditorView {
            return event
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty else {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let combo = KeyCombo(key: chars, modifiers: flags)

        guard let action = lookupTable[combo] else {
            return event
        }

        execute(action)
        return nil // consume the event
    }

    private func isOpenSettingsShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command] else { return false }
        return event.charactersIgnoringModifiers == ","
    }

    private func paneNavigationDirection(for event: NSEvent) -> PaneNode.NavigationDirection? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains([.command, .option]),
              flags.isDisjoint(with: [.control, .shift]) else {
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_LeftArrow:
            return .left
        case kVK_RightArrow:
            return .right
        case kVK_UpArrow:
            return .up
        case kVK_DownArrow:
            return .down
        default:
            return nil
        }
    }

    // MARK: - Action Execution

    private func execute(_ action: KeyBindingAction) {
        guard let manager = workspaceManager else { return }

        switch action {
        case .newTab:
            manager.newTabFromDefaults()

        case .newWindow:
            break

        case .closeTab:
            if let id = manager.activeTabID {
                manager.closeTab(id: id)
            }

        case .copy:
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)

        case .paste:
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)

        case .find:
            NSApp.sendAction(NSSelectorFromString("performFindPanelAction:"), to: nil, from: nil)

        case .openSettings:
            settingsOpenCoordinator?.openSettings()

        case .toggleInputBar:
            settingsStore?.settings.inputBarEnabled.toggle()

        case .toggleTUIPassthrough:
            break

        case .splitRight:
            manager.splitActivePaneFromDefaults(direction: .horizontal)

        case .splitDown:
            manager.splitActivePaneFromDefaults(direction: .vertical)

        case .closePane:
            if let id = manager.activePaneID {
                manager.closePane(id: id)
            }

        case .focusNextPane:
            manager.selectNextPane()

        case .focusPrevPane:
            manager.selectPreviousPane()
        }
    }
}
