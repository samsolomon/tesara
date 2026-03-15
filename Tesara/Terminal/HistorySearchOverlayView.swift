import SwiftUI

struct HistorySearchOverlayView: View {
    @ObservedObject var historyController: InputBarHistoryController
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let onAccept: () -> Void
    let onCancel: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    private var dividerOpacity: Double {
        theme.isDarkBackground ? 0.22 : 0.14
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.swiftUIColor(from: theme.foreground).opacity(dividerOpacity))
                .frame(height: 1)

            if !historyController.searchResults.isEmpty {
                resultsList

                Rectangle()
                    .fill(theme.swiftUIColor(from: theme.foreground).opacity(dividerOpacity))
                    .frame(height: 1)
            }

            searchField
        }
        .background(theme.swiftUIColor(from: theme.background))
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize * 0.85))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground).opacity(0.3))

            TextField("Search history...", text: $historyController.searchQuery)
                .textFieldStyle(.plain)
                .font(.custom(fontFamily, size: fontSize))
                .foregroundStyle(theme.swiftUIColor(from: theme.foreground))
                .focused($isSearchFieldFocused)
                .onSubmit { onAccept() }
                .onChange(of: historyController.searchQuery) { _, newQuery in
                    historyController.updateSearch(query: newQuery)
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selectPrevious()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selectNext()
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(historyController.searchResults.prefix(8).enumerated()), id: \.offset) { index, command in
                        resultRow(command: command, index: index)
                            .id(index)
                    }
                }
            }
            .frame(maxHeight: CGFloat(min(historyController.searchResults.count, 8)) * (fontSize * 1.5 + 12))
            .onChange(of: historyController.selectedSearchIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
    }

    private func resultRow(command: String, index: Int) -> some View {
        let isSelected = index == historyController.selectedSearchIndex
        return Text(command)
            .font(.custom(fontFamily, size: fontSize))
            .foregroundStyle(theme.swiftUIColor(from: theme.foreground))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? theme.swiftUIColor(from: theme.blue).opacity(0.3) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                historyController.selectedSearchIndex = index
                onAccept()
            }
    }

    private func selectNext() {
        let count = min(historyController.searchResults.count, 8)
        guard count > 0 else { return }
        historyController.selectedSearchIndex = min(historyController.selectedSearchIndex + 1, count - 1)
    }

    private func selectPrevious() {
        guard historyController.selectedSearchIndex > 0 else { return }
        historyController.selectedSearchIndex -= 1
    }
}
