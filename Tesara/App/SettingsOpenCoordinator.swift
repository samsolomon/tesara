import SwiftUI

@MainActor
final class SettingsOpenCoordinator: ObservableObject {
    private var action: (@MainActor () -> Void)?

    func setAction(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func openSettings() {
        action?()
    }
}
