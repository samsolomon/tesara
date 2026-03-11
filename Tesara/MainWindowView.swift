import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selection: NavigationItem? = .session

    private enum NavigationItem: Hashable {
        case session
        case history
        case settings
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Session", systemImage: "terminal")
                    .tag(NavigationItem.session)
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(NavigationItem.history)
                Label("Settings", systemImage: "gearshape")
                    .tag(NavigationItem.settings)
            }
            .listStyle(.sidebar)
            .navigationTitle("Tesara")
        } detail: {
            detailView
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .session {
        case .session:
            TerminalWorkspaceView()
        case .history:
            placeholderCard(
                title: "Block History",
                detail: "GRDB-backed block history lands in Session 2 after OSC 133 parsing is in place."
            )
        case .settings:
            placeholderCard(
                title: "Settings Ready",
                detail: "Use Command-, to open the SwiftUI settings panel. Appearance, shell, keyboard, update, and privacy scaffolding are live."
            )
        }
    }

    private func placeholderCard(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.largeTitle.weight(.semibold))

            Text(detail)
                .foregroundStyle(.secondary)

            GroupBox("Current Defaults") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Font") {
                        Text("\(settingsStore.settings.fontFamily) \(Int(settingsStore.settings.fontSize))")
                    }
                    LabeledContent("Theme") {
                        Text(settingsStore.activeTheme.name)
                    }
                    LabeledContent("Shell") {
                        Text(settingsStore.settings.shellPath)
                    }
                    LabeledContent("Working Directory") {
                        Text(settingsStore.settings.defaultWorkingDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Updates") {
                        Text(settingsStore.settings.updateChecksEnabled ? "Automatic" : "Disabled")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(32)
        .background(settingsStore.activeTheme.swiftUIBackgroundGradient)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(SettingsStore())
}
