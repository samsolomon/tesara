import Foundation

// MARK: - Protocol

protocol CompletionProvider: Sendable {
    func complete(prefix: String, cwd: String?) async -> [CompletionItem]
}

// MARK: - Completion Item

struct CompletionItem: Identifiable, Equatable {
    var id: String { "\(kind)-\(displayText)" }
    let displayText: String
    let insertionText: String
    let icon: String          // SF Symbol name
    let kind: CompletionContext
}

// MARK: - File Path Completion

struct FilePathCompletionProvider: CompletionProvider {
    private static let maxResults = 50

    /// Characters that need backslash-escaping in shell file paths.
    private static let shellMetacharacters = CharacterSet(charactersIn: " \t'\"\\$`!#&|;(){}[]<>?*~")

    func complete(prefix: String, cwd: String?) async -> [CompletionItem] {
        let fm = FileManager.default
        let (dirPath, namePrefix) = splitPath(prefix: prefix, cwd: cwd)

        let includeDotfiles = namePrefix.hasPrefix(".")
        let namePrefixLower = namePrefix.lowercased()

        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        var items: [CompletionItem] = []
        for entry in entries {
            if !includeDotfiles && entry.hasPrefix(".") { continue }

            // Case-insensitive matching (macOS filesystem)
            guard entry.lowercased().hasPrefix(namePrefixLower) else { continue }

            let fullPath = (dirPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            let displayText = isDir.boolValue ? entry + "/" : entry
            let completionSuffix = String(entry.dropFirst(namePrefix.count))
            let escapedSuffix = shellEscape(completionSuffix)
            let insertionText = isDir.boolValue ? escapedSuffix + "/" : escapedSuffix + " "

            let icon = isDir.boolValue ? "folder" : "doc"
            items.append(CompletionItem(displayText: displayText, insertionText: insertionText, icon: icon, kind: .filePath))
        }

        // Directories first, then alphabetical — sort before truncating
        items.sort { a, b in
            let aIsDir = a.displayText.hasSuffix("/")
            let bIsDir = b.displayText.hasSuffix("/")
            if aIsDir != bIsDir { return aIsDir }
            return a.displayText.localizedCaseInsensitiveCompare(b.displayText) == .orderedAscending
        }

        return Array(items.prefix(Self.maxResults))
    }

    private func splitPath(prefix: String, cwd: String?) -> (directory: String, namePrefix: String) {
        // Unescape backslash-escaped characters for filesystem lookup
        let unescaped = shellUnescape(prefix)

        // Empty prefix → list CWD contents
        if unescaped.isEmpty {
            return (cwd ?? FileManager.default.currentDirectoryPath, "")
        }

        let expanded: String
        if unescaped.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = home + unescaped.dropFirst()
        } else if unescaped.hasPrefix("/") {
            expanded = unescaped
        } else {
            expanded = ((cwd ?? FileManager.default.currentDirectoryPath) as NSString).appendingPathComponent(unescaped)
        }

        let nsPath = expanded as NSString
        // If the prefix ends with /, we're listing directory contents
        if unescaped.hasSuffix("/") {
            return (expanded, "")
        }
        return (nsPath.deletingLastPathComponent, nsPath.lastPathComponent)
    }

    private func shellEscape(_ text: String) -> String {
        var result = ""
        for char in text {
            if char.unicodeScalars.contains(where: { Self.shellMetacharacters.contains($0) }) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }

    private func shellUnescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for char in text {
            if escaped {
                result.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else {
                result.append(char)
            }
        }
        return result
    }
}

// MARK: - Command Completion

struct CommandCompletionProvider: CompletionProvider {
    private static let maxResults = 50
    private static let builtins: Set<String> = [
        "alias", "bg", "cd", "command", "declare", "dirs", "echo", "eval",
        "exec", "exit", "export", "fg", "hash", "help", "history", "jobs",
        "kill", "let", "local", "popd", "printf", "pushd", "pwd", "read",
        "readonly", "return", "set", "shift", "source", "test", "times",
        "trap", "type", "typeset", "ulimit", "umask", "unalias", "unset",
        "wait",
    ]

    /// Shared cache of PATH executables.
    private static let cache = CommandCache()

    func complete(prefix: String, cwd: String?) async -> [CompletionItem] {
        guard !prefix.isEmpty else { return [] }

        var items: [CompletionItem] = []

        // Builtins
        for builtin in Self.builtins where builtin.hasPrefix(prefix) {
            items.append(CompletionItem(
                displayText: builtin,
                insertionText: String(builtin.dropFirst(prefix.count)) + " ",
                icon: "terminal",
                kind: .command
            ))
        }

        // PATH executables
        let executables = Self.cache.executables()
        for name in executables where name.hasPrefix(prefix) {
            // Don't duplicate builtins
            if Self.builtins.contains(name) { continue }
            items.append(CompletionItem(
                displayText: name,
                insertionText: String(name.dropFirst(prefix.count)) + " ",
                icon: "gearshape",
                kind: .command
            ))
            if items.count >= Self.maxResults { break }
        }

        items.sort { $0.displayText < $1.displayText }
        return Array(items.prefix(Self.maxResults))
    }
}

/// Thread-safe cache of executable names from $PATH.
private final class CommandCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: [String] = []
    private var cacheTime: Date = .distantPast
    private static let ttl: TimeInterval = 30

    func executables() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if now.timeIntervalSince(cacheTime) < Self.ttl { return cached }

        var seen = Set<String>()
        var result: [String] = []
        let fm = FileManager.default

        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in pathEnv.split(separator: ":").map(String.init) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where !seen.contains(entry) {
                seen.insert(entry)
                result.append(entry)
            }
        }

        result.sort()
        cached = result
        cacheTime = now
        return cached
    }
}

// MARK: - Git Branch Completion

struct GitBranchCompletionProvider: CompletionProvider {
    private static let maxResults = 50

    func complete(prefix: String, cwd: String?) async -> [CompletionItem] {
        guard let cwd else { return [] }
        let branches = GitBranchReader.allBranches(at: cwd)

        var items: [CompletionItem] = []
        for branch in branches {
            // Case-sensitive matching for git branches
            guard branch.hasPrefix(prefix) else { continue }
            items.append(CompletionItem(
                displayText: branch,
                insertionText: String(branch.dropFirst(prefix.count)) + " ",
                icon: "arrow.triangle.branch",
                kind: .gitBranch
            ))
            if items.count >= Self.maxResults { break }
        }
        return items
    }
}
