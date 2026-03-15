import Foundation

@MainActor
final class TabCompletionController: ObservableObject {
    weak var terminalSession: TerminalSession?

    /// Called after dismiss so the owner can resume ghost text.
    var onDismiss: (() -> Void)?

    @Published var isActive = false
    @Published private(set) var completions: [CompletionItem] = []
    @Published var selectedIndex = 0

    private(set) var replacementRange: Range<Int> = 0..<0  // UTF-16 column offsets
    private(set) var replacementLine: Int = 0
    private(set) var context: CompletionContext = .command
    private var allCandidates: [CompletionItem] = []
    private var generation: UInt64 = 0
    private var activeTask: Task<Void, Never>?
    private var currentPrefix: String = ""

    // MARK: - Providers

    private static let fileProvider = FilePathCompletionProvider()
    private static let commandProvider = CommandCompletionProvider()
    private static let gitBranchProvider = GitBranchCompletionProvider()

    // MARK: - Trigger

    func triggerCompletion(lineText: String, line: Int, cursorColumn: Int, cwd: String?) {
        generation &+= 1
        let gen = generation
        activeTask?.cancel()

        let detected = CompletionContext.detect(lineText: lineText, cursorColumn: cursorColumn)
        context = detected.context
        replacementRange = detected.tokenStart..<cursorColumn
        replacementLine = line
        currentPrefix = detected.prefix

        let prefix = detected.prefix
        let provider: CompletionProvider = switch detected.context {
        case .command: Self.commandProvider
        case .filePath: Self.fileProvider
        case .gitBranch: Self.gitBranchProvider
        }

        activeTask = Task {
            let results = await provider.complete(prefix: prefix, cwd: cwd)
            guard !Task.isCancelled, generation == gen else { return }

            allCandidates = results
            if results.isEmpty {
                dismiss()
                return
            }

            if results.count == 1 {
                // Single match — auto-insert without showing popup
                insertCompletion(results[0].insertionText)
                dismiss()
                return
            }

            // Multiple matches — try inserting common prefix first
            let commonPrefix = longestCommonPrefix(results.map(\.insertionText))
            if !commonPrefix.isEmpty {
                insertCompletion(commonPrefix)
                // Update replacement range after insertion
                replacementRange = replacementRange.lowerBound..<(replacementRange.upperBound + commonPrefix.utf16.count)
                currentPrefix = currentPrefix + commonPrefix

                // Re-filter after common prefix insertion
                let filtered = results.filter { $0.insertionText.count > commonPrefix.count }
                    .map { CompletionItem(
                        displayText: $0.displayText,
                        insertionText: String($0.insertionText.dropFirst(commonPrefix.count)),
                        icon: $0.icon,
                        kind: $0.kind
                    )}

                if filtered.isEmpty || filtered.count == 1 {
                    return
                }

                allCandidates = filtered
                completions = filtered
                selectedIndex = 0
                isActive = true
            } else {
                // No common prefix to insert — show popup immediately
                completions = results
                selectedIndex = 0
                isActive = true
            }
        }
    }

    // MARK: - Live Filter

    func updateFilter(lineText: String, cursorColumn: Int) {
        guard isActive else { return }

        let detected = CompletionContext.detect(lineText: lineText, cursorColumn: cursorColumn)

        if detected.context != context {
            dismiss()
            return
        }

        let newPrefix = detected.prefix

        // Re-filter candidates based on new prefix
        let caseSensitive = context == .command || context == .gitBranch
        let filtered = allCandidates.filter { item in
            let full = currentPrefix + item.insertionText
            return caseSensitive ? full.hasPrefix(newPrefix) : full.lowercased().hasPrefix(newPrefix.lowercased())
        }

        if filtered.isEmpty {
            dismiss()
            return
        }

        // Update insertion texts to account for the new prefix.
        // currentPrefix stays fixed (matches allCandidates baseline);
        // only the displayed completions get adjusted insertion texts.
        completions = filtered.map { item in
            let full = currentPrefix + item.insertionText
            let remaining = String(full.dropFirst(newPrefix.count))
            return CompletionItem(displayText: item.displayText, insertionText: remaining, icon: item.icon, kind: item.kind)
        }
        replacementRange = detected.tokenStart..<cursorColumn
        selectedIndex = min(selectedIndex, completions.count - 1)
    }

    // MARK: - Accept

    func acceptSelected() {
        guard isActive, selectedIndex < completions.count else { return }
        insertCompletion(completions[selectedIndex].insertionText)
        dismiss()
    }

    // MARK: - Navigation

    func selectNext() {
        guard !completions.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, completions.count - 1)
    }

    func selectPrevious() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    // MARK: - Dismiss

    func dismiss() {
        guard isActive || activeTask != nil else { return }
        activeTask?.cancel()
        activeTask = nil
        isActive = false
        completions = []
        allCandidates = []
        selectedIndex = 0
        currentPrefix = ""
        onDismiss?()
    }

    // MARK: - Helpers

    private func insertCompletion(_ text: String) {
        guard !text.isEmpty, let session = terminalSession?.inputBarState?.editorSession else { return }
        session.insertText(text)
    }

    private func longestCommonPrefix(_ strings: [String]) -> String {
        guard let first = strings.first, !first.isEmpty else { return "" }
        var endIndex = first.startIndex
        outer: for i in first.indices {
            let ch = first[i]
            for str in strings.dropFirst() {
                if i >= str.endIndex || str[i] != ch { break outer }
            }
            endIndex = first.index(after: i)
        }
        return String(first[first.startIndex..<endIndex])
    }
}
