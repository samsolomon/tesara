import Foundation

@MainActor
final class InputBarHistoryController: ObservableObject {
    weak var blockStore: BlockStore?

    @Published var isSearchActive = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [String] = []
    @Published var selectedSearchIndex = 0

    private var historyIndex = -1
    private var savedCurrentInput = ""
    private var cachedHistory: [String] = []

    // MARK: - Up/Down Navigation

    func navigateUp(currentText: String, inputBarState: InputBarState) {
        if historyIndex == -1 {
            refreshHistory()
            savedCurrentInput = currentText
        }

        let candidates: [String]
        if !savedCurrentInput.isEmpty {
            candidates = cachedHistory.filter { $0.hasPrefix(savedCurrentInput) }
        } else {
            candidates = cachedHistory
        }

        guard !candidates.isEmpty else { return }

        let nextIndex = historyIndex + 1
        guard nextIndex < candidates.count else { return }
        historyIndex = nextIndex
        inputBarState.setText(candidates[nextIndex])
    }

    func navigateDown(currentText: String, inputBarState: InputBarState) {
        guard historyIndex >= 0 else { return }

        let candidates: [String]
        if !savedCurrentInput.isEmpty {
            candidates = cachedHistory.filter { $0.hasPrefix(savedCurrentInput) }
        } else {
            candidates = cachedHistory
        }

        historyIndex -= 1
        if historyIndex < 0 {
            historyIndex = -1
            inputBarState.setText(savedCurrentInput)
        } else if historyIndex < candidates.count {
            inputBarState.setText(candidates[historyIndex])
        }
    }

    // MARK: - Search (Ctrl+R)

    func beginSearch() {
        isSearchActive = true
        searchQuery = ""
        searchResults = []
        selectedSearchIndex = 0
    }

    func updateSearch(query: String) {
        searchQuery = query
        guard !query.isEmpty else {
            searchResults = []
            selectedSearchIndex = 0
            return
        }
        searchResults = blockStore?.searchCommands(query: query) ?? []
        selectedSearchIndex = 0
    }

    func acceptSearchResult(inputBarState: InputBarState) {
        guard isSearchActive, !searchResults.isEmpty,
              selectedSearchIndex < searchResults.count else {
            cancelSearch()
            return
        }
        let command = searchResults[selectedSearchIndex]
        isSearchActive = false
        searchQuery = ""
        searchResults = []
        inputBarState.setText(command)
    }

    func cancelSearch() {
        isSearchActive = false
        searchQuery = ""
        searchResults = []
        selectedSearchIndex = 0
    }

    // MARK: - Reset

    func reset() {
        historyIndex = -1
        savedCurrentInput = ""
        cancelSearch()
    }

    // MARK: - Private

    private func refreshHistory() {
        cachedHistory = blockStore?.recentCommandTexts() ?? []
    }
}
