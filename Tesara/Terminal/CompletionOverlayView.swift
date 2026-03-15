import SwiftUI

struct CompletionOverlayView: View {
    @ObservedObject var completionController: TabCompletionController
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(theme.dividerOpacity))
                .frame(height: 1)

            resultsList
        }
        .background(theme.swiftUIColor(from: theme.background))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab completions")
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(completionController.completions.prefix(8).enumerated()), id: \.element.id) { index, item in
                        resultRow(item: item, index: index)
                            .id(index)
                    }
                }
            }
            .frame(maxHeight: CGFloat(min(completionController.completions.count, 8)) * (fontSize * 1.5 + 12))
            .onChange(of: completionController.selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func resultRow(item: CompletionItem, index: Int) -> some View {
        let isSelected = index == completionController.selectedIndex
        return HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: fontSize * 0.85))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.4))
                .frame(width: fontSize * 1.2)

            Text(item.displayText)
                .font(.custom(fontFamily, size: fontSize))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(kindLabel(item.kind))
                .font(.custom(fontFamily, size: fontSize * 0.8))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? theme.swiftUIColor(from: theme.blue).opacity(0.3) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            completionController.selectedIndex = index
            completionController.acceptSelected()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.displayText), \(kindLabel(item.kind))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func kindLabel(_ kind: CompletionContext) -> String {
        switch kind {
        case .command: "command"
        case .filePath: "path"
        case .gitBranch: "branch"
        }
    }
}
