import Foundation

@MainActor
final class InputBarHistoryController: ObservableObject {
    weak var blockStore: BlockStore?

    @Published var isSearchActive = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [String] = []
    @Published var selectedSearchIndex = 0

    @Published var isPopupActive = false
    @Published private(set) var popupItems: [String] = []
    @Published private(set) var selectedPopupIndex = 0
    private var savedPopupInput = ""

    // MARK: - History Popup

    func openPopup(currentText: String, inputBarState: InputBarState) {
        let history = blockStore?.recentCommandTexts() ?? []
        savedPopupInput = currentText

        let candidates: [String]
        if currentText.isEmpty {
            candidates = history
        } else {
            candidates = history.filter { $0.hasPrefix(currentText) }
        }

        let items = Array(candidates.prefix(10))
        guard !items.isEmpty else { return }

        popupItems = items
        selectedPopupIndex = 0
        isPopupActive = true
        inputBarState.setText(items[0])
    }

    func popupSelectPrevious(inputBarState: InputBarState) {
        guard selectedPopupIndex > 0 else { return }
        selectedPopupIndex -= 1
        inputBarState.setText(popupItems[selectedPopupIndex])
    }

    func popupSelectNext(inputBarState: InputBarState) {
        guard selectedPopupIndex < popupItems.count - 1 else { return }
        selectedPopupIndex += 1
        inputBarState.setText(popupItems[selectedPopupIndex])
    }

    func dismissPopup(inputBarState: InputBarState) {
        inputBarState.setText(savedPopupInput)
        dismissPopupSilently()
    }

    func dismissPopupSilently() {
        guard isPopupActive else { return }
        isPopupActive = false
        popupItems = []
        selectedPopupIndex = 0
        savedPopupInput = ""
    }

    func acceptPopupSelection() {
        dismissPopupSilently()
    }

    func acceptPopupItem(at index: Int, inputBarState: InputBarState) {
        guard index >= 0, index < popupItems.count else { return }
        inputBarState.setText(popupItems[index])
        dismissPopupSilently()
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
        dismissPopupSilently()
        cancelSearch()
    }

}
