import SwiftUI

@main
struct TesaraApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(settingsStore)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            TesaraAppCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .frame(width: 720, height: 520)
        }
    }
}
