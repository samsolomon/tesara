import SwiftUI

struct SettingsSidebarView: View {
    @ObservedObject var paneSelection: SettingsPaneSelection

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        paneSelection.pane = pane
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pane.systemImage)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 18)

                            Text(pane.title)
                                .font(.system(size: 14, weight: .medium))

                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(paneSelection.pane == pane ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(paneSelection.pane == pane ? Color.accentColor : Color.clear)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }
}
