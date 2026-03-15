import Foundation

@MainActor
final class SuggestionEngine {
    weak var blockStore: BlockStore?
    private var cachedCommands: [String] = []
    private var cacheTimestamp: Date = .distantPast

    /// Returns the full matching command, or nil. Caller computes suffix.
    func suggest(prefix: String) -> String? {
        guard !prefix.isEmpty else { return nil }
        refreshCacheIfNeeded()
        for command in cachedCommands {
            if command.hasPrefix(prefix) && command != prefix {
                return command
            }
        }
        return nil
    }

    /// Mark cache stale (call after a new command is recorded).
    func invalidateCache() {
        cacheTimestamp = .distantPast
    }

    private func refreshCacheIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(cacheTimestamp) > 2 else { return }
        cachedCommands = blockStore?.recentCommandTexts(limit: 500) ?? []
        cacheTimestamp = now
    }
}
