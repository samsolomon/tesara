import SwiftUI

struct HistoryPopupView: View {
    @ObservedObject var historyController: InputBarHistoryController
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let onAccept: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(theme.dividerOpacity))
                .frame(height: 1)

            resultsList

            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(theme.dividerOpacity))
                .frame(height: 1)

            hintBar
        }
        .background(theme.swiftUIColor(from: theme.background))
        .accessibilityLabel("Command history")
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(historyController.popupItems.enumerated()), id: \.offset) { index, command in
                resultRow(command: command, index: index)
            }
        }
    }

    private func resultRow(command: String, index: Int) -> some View {
        let isSelected = index == historyController.selectedPopupIndex
        return Text(command)
            .font(.custom(fontFamily, size: fontSize * 0.85))
            .foregroundStyle(theme.swiftUIColor(from: theme.foreground))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? theme.swiftUIColor(from: theme.cursor).opacity(0.2) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                onAccept(index)
            }
    }

    private var hintBar: some View {
        Text("\u{2191} \u{2193} to navigate  esc to dismiss")
            .font(.custom(fontFamily, size: fontSize * 0.8))
            .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
