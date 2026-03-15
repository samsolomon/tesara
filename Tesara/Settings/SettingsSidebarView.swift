import SwiftUI

struct SettingsSidebarView: View {
    @ObservedObject var paneSelection: SettingsPaneSelection

    private var selection: Binding<SettingsPane?> {
        Binding<SettingsPane?>(
            get: { paneSelection.pane },
            set: { paneSelection.pane = $0 ?? .appearance }
        )
    }

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 8)
        }
    }
}
