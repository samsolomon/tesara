import XCTest
@testable import Tesara

// MARK: - CompletionContext.detect Tests

final class CompletionContextTests: XCTestCase {

    // MARK: - Empty / Cursor at Start

    func testEmptyLineReturnsCommand() {
        let result = CompletionContext.detect(lineText: "", cursorColumn: 0)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.tokenStart, 0)
        XCTAssertEqual(result.prefix, "")
    }

    // MARK: - Command Context (First Token)

    func testFirstTokenIsCommand() {
        let result = CompletionContext.detect(lineText: "ls", cursorColumn: 2)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "ls")
        XCTAssertEqual(result.tokenStart, 0)
    }

    func testPartialFirstTokenIsCommand() {
        let result = CompletionContext.detect(lineText: "nod", cursorColumn: 3)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "nod")
    }

    func testCursorInMiddleOfFirstToken() {
        let result = CompletionContext.detect(lineText: "grep", cursorColumn: 2)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "gr")
        XCTAssertEqual(result.tokenStart, 0)
    }

    // MARK: - File Path Context (Arguments)

    func testSecondTokenIsFilePath() {
        let result = CompletionContext.detect(lineText: "ls Doc", cursorColumn: 6)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "Doc")
        XCTAssertEqual(result.tokenStart, 3)
    }

    func testEmptySecondTokenIsFilePath() {
        let result = CompletionContext.detect(lineText: "ls ", cursorColumn: 3)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "")
        XCTAssertEqual(result.tokenStart, 3)
    }

    func testTildePathIsFilePath() {
        let result = CompletionContext.detect(lineText: "cat ~/Doc", cursorColumn: 9)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "~/Doc")
    }

    func testAbsolutePathIsFilePath() {
        let result = CompletionContext.detect(lineText: "cat /usr/lo", cursorColumn: 11)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "/usr/lo")
    }

    func testThirdTokenIsFilePath() {
        let result = CompletionContext.detect(lineText: "cp foo bar", cursorColumn: 10)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "bar")
    }

    // MARK: - Command Context After Pipe / Operators

    func testAfterPipeIsCommand() {
        let result = CompletionContext.detect(lineText: "cat foo.txt | gre", cursorColumn: 17)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "gre")
    }

    func testAfterSemicolonIsCommand() {
        let result = CompletionContext.detect(lineText: "cd /tmp; ls", cursorColumn: 11)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "ls")
    }

    func testAfterAndAndIsCommand() {
        let result = CompletionContext.detect(lineText: "make && ./ru", cursorColumn: 12)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "./ru")
    }

    func testAfterOrOrIsCommand() {
        let result = CompletionContext.detect(lineText: "test -f x || ech", cursorColumn: 17)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "ech")
    }

    func testEmptyAfterPipeIsCommand() {
        let result = CompletionContext.detect(lineText: "ls | ", cursorColumn: 5)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "")
    }

    // MARK: - Git Branch Context

    func testGitCheckoutIsGitBranch() {
        let result = CompletionContext.detect(lineText: "git checkout ", cursorColumn: 13)
        XCTAssertEqual(result.context, .gitBranch)
        XCTAssertEqual(result.prefix, "")
    }

    func testGitCheckoutPrefixIsGitBranch() {
        let result = CompletionContext.detect(lineText: "git checkout fea", cursorColumn: 16)
        XCTAssertEqual(result.context, .gitBranch)
        XCTAssertEqual(result.prefix, "fea")
    }

    func testGitSwitchIsGitBranch() {
        let result = CompletionContext.detect(lineText: "git switch ma", cursorColumn: 13)
        XCTAssertEqual(result.context, .gitBranch)
        XCTAssertEqual(result.prefix, "ma")
    }

    func testGitMergeIsGitBranch() {
        let result = CompletionContext.detect(lineText: "git merge ", cursorColumn: 10)
        XCTAssertEqual(result.context, .gitBranch)
    }

    func testGitRebaseIsGitBranch() {
        let result = CompletionContext.detect(lineText: "git rebase ", cursorColumn: 11)
        XCTAssertEqual(result.context, .gitBranch)
    }

    func testGitCheckoutFlagIsNotBranch() {
        // "git checkout -b" — the -b flag itself is not a branch name
        let result = CompletionContext.detect(lineText: "git checkout -b", cursorColumn: 15)
        // -b starts with "-", so this is .argument (filePath), not gitBranch
        XCTAssertNotEqual(result.context, .gitBranch)
    }

    func testGitSubcommandItselfIsNotBranch() {
        // "git check" — completing the subcommand, not a branch
        let result = CompletionContext.detect(lineText: "git check", cursorColumn: 9)
        XCTAssertEqual(result.context, .filePath) // second token = argument
    }

    func testGitAloneIsCommand() {
        let result = CompletionContext.detect(lineText: "git", cursorColumn: 3)
        XCTAssertEqual(result.context, .command)
    }

    func testNonBranchGitSubcommandIsFilePath() {
        // "git add " — 'add' is not in gitBranchSubcommands
        let result = CompletionContext.detect(lineText: "git add ", cursorColumn: 8)
        XCTAssertEqual(result.context, .filePath)
    }

    // MARK: - Quoted Strings

    func testSingleQuotedToken() {
        let result = CompletionContext.detect(lineText: "echo 'hello wor", cursorColumn: 16)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "'hello wor")
    }

    func testDoubleQuotedToken() {
        let result = CompletionContext.detect(lineText: "echo \"hello", cursorColumn: 11)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.prefix, "\"hello")
    }

    // MARK: - UTF-16 Consistency

    func testTokenStartIsUTF16() {
        // Verify UTF-16 column offsets with an ASCII multi-token line
        let result = CompletionContext.detect(lineText: "ls foo", cursorColumn: 5)
        XCTAssertEqual(result.context, .filePath)
        XCTAssertEqual(result.tokenStart, 3)
        XCTAssertEqual(result.prefix, "fo")
    }

    // MARK: - Edge Cases

    func testCursorBeyondLineLength() {
        let result = CompletionContext.detect(lineText: "ls", cursorColumn: 100)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "ls")
    }

    func testOnlyWhitespace() {
        let result = CompletionContext.detect(lineText: "   ", cursorColumn: 3)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "")
    }

    func testMultiplePipes() {
        let result = CompletionContext.detect(lineText: "cat f | grep x | so", cursorColumn: 19)
        XCTAssertEqual(result.context, .command)
        XCTAssertEqual(result.prefix, "so")
    }
}

// MARK: - FilePathCompletionProvider Tests

final class FilePathCompletionProviderTests: XCTestCase {
    private let provider = FilePathCompletionProvider()
    private var testDir: String!

    override func setUp() async throws {
        try await super.setUp()
        testDir = NSTemporaryDirectory() + "tesara-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        // Create test files
        fm.createFile(atPath: (testDir as NSString).appendingPathComponent("file1.txt"), contents: nil)
        fm.createFile(atPath: (testDir as NSString).appendingPathComponent("file2.txt"), contents: nil)
        fm.createFile(atPath: (testDir as NSString).appendingPathComponent("README.md"), contents: nil)
        fm.createFile(atPath: (testDir as NSString).appendingPathComponent(".hidden"), contents: nil)
        fm.createFile(atPath: (testDir as NSString).appendingPathComponent("my file.txt"), contents: nil)
        try fm.createDirectory(atPath: (testDir as NSString).appendingPathComponent("subdir"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (testDir as NSString).appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (testDir as NSString).appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDir)
        try await super.tearDown()
    }

    func testEmptyPrefixListsCWD() async {
        let items = await provider.complete(prefix: "", cwd: testDir)
        XCTAssertFalse(items.isEmpty)
    }

    func testPrefixFiltersResults() async {
        let items = await provider.complete(prefix: "file", cwd: testDir)
        XCTAssertEqual(items.count, 2) // file1.txt, file2.txt
        for item in items {
            XCTAssertTrue(item.displayText.hasPrefix("file"))
        }
    }

    func testCaseInsensitiveMatching() async {
        let items = await provider.complete(prefix: "read", cwd: testDir)
        XCTAssertTrue(items.contains { $0.displayText == "README.md" })
    }

    func testDotPrefixShowsDotfiles() async {
        let items = await provider.complete(prefix: ".", cwd: testDir)
        XCTAssertTrue(items.contains { $0.displayText == ".hidden" })
    }

    func testNoDotPrefixHidesDotfiles() async {
        let items = await provider.complete(prefix: "", cwd: testDir)
        XCTAssertFalse(items.contains { $0.displayText == ".hidden" })
    }

    func testDirectoriesGetTrailingSlash() async {
        let items = await provider.complete(prefix: "sub", cwd: testDir)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayText, "subdir/")
        XCTAssertTrue(items[0].insertionText.hasSuffix("/"))
    }

    func testDirectoriesSortFirst() async {
        let items = await provider.complete(prefix: "", cwd: testDir)
        // Find the first non-directory
        if let firstFileIndex = items.firstIndex(where: { !$0.displayText.hasSuffix("/") }),
           let lastDirIndex = items.lastIndex(where: { $0.displayText.hasSuffix("/") }) {
            XCTAssertLessThan(lastDirIndex, firstFileIndex)
        }
    }

    func testSpacesAreEscaped() async {
        let items = await provider.complete(prefix: "my", cwd: testDir)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].insertionText.contains("\\"))
        XCTAssertEqual(items[0].displayText, "my file.txt")
    }

    func testTrailingSlashListsDirectoryContents() async {
        let items = await provider.complete(prefix: "subdir/", cwd: testDir)
        // subdir is empty, should return nothing
        XCTAssertTrue(items.isEmpty)
    }

    func testNonexistentDirectoryReturnsEmpty() async {
        let items = await provider.complete(prefix: "nonexistent/foo", cwd: testDir)
        XCTAssertTrue(items.isEmpty)
    }

    func testMultipleDirMatchesWithCommonPrefix() async {
        let items = await provider.complete(prefix: "Do", cwd: testDir)
        XCTAssertEqual(items.count, 2) // Documents/, Downloads/
        for item in items {
            XCTAssertTrue(item.displayText.hasPrefix("Do"))
        }
    }

    func testInsertionTextIsRemainder() async {
        let items = await provider.complete(prefix: "file1", cwd: testDir)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayText, "file1.txt")
        XCTAssertEqual(items[0].insertionText, ".txt ")
    }

    func testDirectoryCompletionHasNoTrailingSpace() async {
        let items = await provider.complete(prefix: "sub", cwd: testDir)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayText, "subdir/")
        XCTAssertTrue(items[0].insertionText.hasSuffix("/"))
        XCTAssertFalse(items[0].insertionText.hasSuffix(" "))
    }
}

// MARK: - CommandCompletionProvider Tests

final class CommandCompletionProviderTests: XCTestCase {
    private let provider = CommandCompletionProvider()

    func testFindsBuiltins() async {
        let items = await provider.complete(prefix: "cd", cwd: nil)
        XCTAssertTrue(items.contains { $0.displayText == "cd" })
    }

    func testFindsPathExecutables() async {
        // "ls" should exist on any macOS system
        let items = await provider.complete(prefix: "ls", cwd: nil)
        XCTAssertTrue(items.contains { $0.displayText == "ls" })
    }

    func testPrefixFiltersCaseSensitive() async {
        let items = await provider.complete(prefix: "CD", cwd: nil)
        // "cd" builtin should NOT match "CD" (case-sensitive)
        XCTAssertFalse(items.contains { $0.displayText == "cd" })
    }

    func testEmptyPrefixReturnsEmpty() async {
        let items = await provider.complete(prefix: "", cwd: nil)
        XCTAssertTrue(items.isEmpty)
    }

    func testResultsAreSorted() async {
        let items = await provider.complete(prefix: "l", cwd: nil)
        let names = items.map(\.displayText)
        XCTAssertEqual(names, names.sorted())
    }

    func testInsertionTextIsRemainder() async {
        let items = await provider.complete(prefix: "ech", cwd: nil)
        if let echo = items.first(where: { $0.displayText == "echo" }) {
            XCTAssertEqual(echo.insertionText, "o ")
        }
    }
}

// MARK: - TabCompletionController Tests

@MainActor
final class TabCompletionControllerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let controller = TabCompletionController()
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.completions.isEmpty)
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    // MARK: - Navigation

    func testSelectNextClampsToEnd() {
        let controller = TabCompletionController()
        // No completions — should be no-op
        controller.selectNext()
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    func testSelectPreviousClampsToZero() {
        let controller = TabCompletionController()
        controller.selectPrevious()
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    // MARK: - Dismiss

    func testDismissResetsState() {
        let controller = TabCompletionController()
        var dismissed = false
        controller.onDismiss = { dismissed = true }

        // Force active state for test
        controller.isActive = true
        controller.dismiss()

        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(controller.completions.isEmpty)
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertTrue(dismissed)
    }

    func testDismissWhenAlreadyInactiveIsNoOp() {
        let controller = TabCompletionController()
        var called = false
        controller.onDismiss = { called = true }
        controller.dismiss()
        XCTAssertFalse(called)
    }

    // MARK: - Update Filter

    func testUpdateFilterWhenInactiveIsNoOp() {
        let controller = TabCompletionController()
        // Should not crash or change state
        controller.updateFilter(lineText: "ls foo", cursorColumn: 6)
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - Accept

    func testAcceptSelectedWhenInactiveIsNoOp() {
        let controller = TabCompletionController()
        // Should not crash
        controller.acceptSelected()
        XCTAssertFalse(controller.isActive)
    }

}

// MARK: - GitBranchReader.allBranches Tests

final class GitBranchReaderTests: XCTestCase {
    private var testDir: String!

    override func setUp() async throws {
        try await super.setUp()
        testDir = NSTemporaryDirectory() + "tesara-git-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: testDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDir)
        try await super.tearDown()
    }

    private func createGitRepo(branches: [String]) throws {
        let fm = FileManager.default
        let gitDir = (testDir as NSString).appendingPathComponent(".git")
        try fm.createDirectory(atPath: gitDir, withIntermediateDirectories: true)

        // Write HEAD
        let headPath = (gitDir as NSString).appendingPathComponent("HEAD")
        try "ref: refs/heads/main\n".write(toFile: headPath, atomically: true, encoding: .utf8)

        // Create refs/heads/ with branch files
        let refsHeads = (gitDir as NSString).appendingPathComponent("refs/heads")
        try fm.createDirectory(atPath: refsHeads, withIntermediateDirectories: true)

        for branch in branches {
            let branchPath = (refsHeads as NSString).appendingPathComponent(branch)
            let parentDir = (branchPath as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: parentDir) {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            }
            try "abc1234\n".write(toFile: branchPath, atomically: true, encoding: .utf8)
        }
    }

    func testAllBranchesReturnsLooseRefs() throws {
        try createGitRepo(branches: ["main", "feature/login", "develop"])
        let branches = GitBranchReader.allBranches(at: testDir)
        XCTAssertTrue(branches.contains("main"))
        XCTAssertTrue(branches.contains("feature/login"))
        XCTAssertTrue(branches.contains("develop"))
    }

    func testAllBranchesIsSorted() throws {
        try createGitRepo(branches: ["zebra", "alpha", "middle"])
        let branches = GitBranchReader.allBranches(at: testDir)
        XCTAssertEqual(branches, branches.sorted())
    }

    func testAllBranchesWithPackedRefs() throws {
        try createGitRepo(branches: ["main"])

        // Add a packed-refs file with additional branches
        let gitDir = (testDir as NSString).appendingPathComponent(".git")
        let packedRefsPath = (gitDir as NSString).appendingPathComponent("packed-refs")
        let content = """
        # pack-refs with: peeled fully-peeled sorted
        abc1234567890 refs/heads/packed-branch
        def5678901234 refs/heads/another-packed
        abc1234567890 refs/tags/v1.0
        """
        try content.write(toFile: packedRefsPath, atomically: true, encoding: .utf8)

        let branches = GitBranchReader.allBranches(at: testDir)
        XCTAssertTrue(branches.contains("main"))           // from loose refs
        XCTAssertTrue(branches.contains("packed-branch"))   // from packed-refs
        XCTAssertTrue(branches.contains("another-packed"))  // from packed-refs
        XCTAssertFalse(branches.contains("v1.0"))           // tags should not appear
    }

    func testAllBranchesNonGitDirReturnsEmpty() {
        let branches = GitBranchReader.allBranches(at: testDir)
        XCTAssertTrue(branches.isEmpty)
    }

    func testAllBranchesDeduplicatesLooseAndPacked() throws {
        try createGitRepo(branches: ["main", "develop"])

        let gitDir = (testDir as NSString).appendingPathComponent(".git")
        let packedRefsPath = (gitDir as NSString).appendingPathComponent("packed-refs")
        try "abc1234 refs/heads/main\nabc1234 refs/heads/develop\n".write(toFile: packedRefsPath, atomically: true, encoding: .utf8)

        let branches = GitBranchReader.allBranches(at: testDir)
        // Should not have duplicates
        XCTAssertEqual(branches.count, Set(branches).count)
    }
}
