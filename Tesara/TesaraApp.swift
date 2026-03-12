import SwiftUI

@main
struct TesaraApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var blockStore = BlockStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            TesaraAppCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(blockStore)
                .frame(width: 720, height: 520)
        }
    }
}
