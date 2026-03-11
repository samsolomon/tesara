import AppKit
import SwiftUI

struct TesaraAppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
        }
    }
}
