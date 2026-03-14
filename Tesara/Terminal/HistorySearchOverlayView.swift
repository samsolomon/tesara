import SwiftUI

struct HistorySearchOverlayView: View {
    @ObservedObject var historyController: InputBarHistoryController
    let theme: TerminalTheme
    let fontFamily: String
    let fontSize: Double
    let onAccept: () -> Void
    let onCancel: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    private var isDarkTheme: Bool { theme.isDarkBackground }

    var body: some View {
        VStack(spacing: 0) {
            if !historyController.searchResults.isEmpty {
                resultsList
            }
            searchField
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background { searchBackground }
        .shadow(color: .black.opacity(isDarkTheme ? 0.5 : 0.2), radius: 12, y: 4)
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize * 0.85))
                .foregroundStyle(.secondary)

            TextField("Search history...", text: $historyController.searchQuery)
                .textFieldStyle(.plain)
                .font(.custom(fontFamily, size: fontSize))
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

    @ViewBuilder
    private var searchBackground: some View {
        if #available(macOS 26, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(isDarkTheme ? 0.15 : 0.08), lineWidth: 0.5)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(isDarkTheme ? 0.12 : 0.06), lineWidth: 0.5)
                }
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
