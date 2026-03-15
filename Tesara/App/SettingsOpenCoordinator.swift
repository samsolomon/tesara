import AppKit
import SwiftUI

@MainActor
final class SettingsOpenCoordinator: ObservableObject {
    func openSettings() {
        NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
