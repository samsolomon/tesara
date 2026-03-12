import XCTest
import GRDB
@testable import Tesara

@MainActor
final class BlockStoreTests: XCTestCase {
    private func makeStore() throws -> BlockStore {
        try BlockStore(dbQueue: DatabaseQueue())
    }

    func testStartSessionReturnsUUID() throws {
        let store = try makeStore()
        let id = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertFalse(id.uuidString.isEmpty)
    }

    func testRoundTripRecordAndReload() throws {
        let store = try makeStore()
        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        let block = TerminalBlockCapture(
            commandText: "echo hello",
            outputText: "hello",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            stage: .output
        )

        let didPersist = store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        XCTAssertTrue(didPersist)

        store.reloadRecentBlocks()
        XCTAssertEqual(store.recentBlocks.count, 1)

        let summary = store.recentBlocks[0]
        XCTAssertEqual(summary.commandText, "echo hello")
        XCTAssertEqual(summary.outputText, "hello")
        XCTAssertEqual(summary.exitCode, 0)
        XCTAssertEqual(summary.shellPath, "/bin/zsh")
        XCTAssertEqual(summary.workingDirectory, "/tmp")
    }

    func testEmptyCommandIsRejected() throws {
        let store = try makeStore()
        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        let block = TerminalBlockCapture(
            commandText: "   ",
            outputText: "output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            stage: .output
        )

        let didPersist = store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        XCTAssertFalse(didPersist)

        store.reloadRecentBlocks()
        XCTAssertTrue(store.recentBlocks.isEmpty)
    }

    func testMultipleBlocksOrdering() throws {
        let store = try makeStore()
        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        let now = Date()
        for i in 0..<3 {
            let block = TerminalBlockCapture(
                commandText: "cmd\(i)",
                outputText: "out\(i)",
                exitCode: 0,
                startedAt: now.addingTimeInterval(Double(i)),
                finishedAt: now.addingTimeInterval(Double(i) + 0.5),
                stage: .output
            )
            store.recordBlock(sessionID: sessionID, block: block, orderIndex: i)
        }

        store.reloadRecentBlocks()
        XCTAssertEqual(store.recentBlocks.count, 3)
        // Most recent first (ORDER BY startedAt DESC)
        XCTAssertEqual(store.recentBlocks[0].commandText, "cmd2")
        XCTAssertEqual(store.recentBlocks[1].commandText, "cmd1")
        XCTAssertEqual(store.recentBlocks[2].commandText, "cmd0")
    }

    func testNoStartupErrorForInMemoryDB() throws {
        let store = try makeStore()
        XCTAssertNil(store.startupErrorMessage)
    }

    func testReloadRecentBlocksLimit() throws {
        let store = try makeStore()
        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        let now = Date()
        for i in 0..<5 {
            let block = TerminalBlockCapture(
                commandText: "cmd\(i)",
                outputText: "",
                exitCode: 0,
                startedAt: now.addingTimeInterval(Double(i)),
                finishedAt: now.addingTimeInterval(Double(i) + 0.1),
                stage: .output
            )
            store.recordBlock(sessionID: sessionID, block: block, orderIndex: i)
        }

        store.reloadRecentBlocks(limit: 2)
        XCTAssertEqual(store.recentBlocks.count, 2)
    }
}
