import Foundation

enum GitBranchReader {
    private static let branchRefPrefix = "ref: refs/heads/"
    private static let refPrefix = "ref: refs/"
    private static let gitdirPrefix = "gitdir: "

    /// Returns the current git branch name for the given directory, or `nil` if not in a git repo.
    /// Walks up the directory tree looking for `.git`. Supports worktrees and submodules.
    static func branch(at directory: String) -> String? {
        guard let gitPath = findGitPath(from: directory) else { return nil }
        let headPath = (gitPath as NSString).appendingPathComponent("HEAD")
        guard let data = FileManager.default.contents(atPath: headPath),
              let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }

        if content.hasPrefix(branchRefPrefix) {
            return String(content.dropFirst(branchRefPrefix.count))
        }
        if content.hasPrefix(refPrefix) {
            return (content as NSString).lastPathComponent
        }
        // Detached HEAD — return short SHA
        if content.count >= 7 {
            return String(content.prefix(7))
        }
        return nil
    }

    /// Returns all local branch names for the given directory.
    /// Enumerates refs/heads/ recursively and parses packed-refs.
    static func allBranches(at directory: String) -> [String] {
        guard let gitPath = findGitPath(from: directory) else { return [] }

        let fm = FileManager.default
        var branches = Set<String>()

        // 1. Enumerate refs/heads/ recursively (loose refs)
        let refsHeads = (gitPath as NSString).appendingPathComponent("refs/heads")
        if let enumerator = fm.enumerator(atPath: refsHeads) {
            while let relative = enumerator.nextObject() as? String {
                let fullPath = (refsHeads as NSString).appendingPathComponent(relative)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    branches.insert(relative)
                }
            }
        }

        // 2. Parse packed-refs for additional branches
        let packedRefsPath = (gitPath as NSString).appendingPathComponent("packed-refs")
        if let data = fm.contents(atPath: packedRefsPath),
           let content = String(data: data, encoding: .utf8) {
            let prefix = "refs/heads/"
            for line in content.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("^") else { continue }
                // Format: <sha> <ref>
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let ref = String(parts[1])
                if ref.hasPrefix(prefix) {
                    branches.insert(String(ref.dropFirst(prefix.count)))
                }
            }
        }

        return branches.sorted()
    }

    /// Walks up from `directory` looking for `.git` (directory or file).
    /// Returns the path to the git directory containing HEAD.
    private static func findGitPath(from directory: String) -> String? {
        let fm = FileManager.default
        var current = directory

        while true {
            let dotGit = (current as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
                if isDir.boolValue {
                    return dotGit
                }
                // .git file (worktree/submodule) — parse `gitdir: <path>`
                if let data = fm.contents(atPath: dotGit),
                   let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   content.hasPrefix(gitdirPrefix) {
                    let relative = String(content.dropFirst(gitdirPrefix.count))
                    if (relative as NSString).isAbsolutePath {
                        return relative
                    }
                    return (current as NSString).appendingPathComponent(relative)
                }
            }

            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
        return nil
    }
}
