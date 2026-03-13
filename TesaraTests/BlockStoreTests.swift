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

    /// Wait for background writes dispatched to .utility to complete and reload on main.
    private func waitForAsyncWrites() {
        // Enqueue a barrier on the same QoS tier to ensure prior dispatches complete,
        // then hop back to main to process any scheduled reloads.
        let expectation = XCTestExpectation(description: "async writes")
        DispatchQueue.global(qos: .utility).async {
            // By the time this runs, prior .utility dispatches have been submitted.
            // But DatabaseQueue serializes, so wait once more to let DB writes finish.
            DispatchQueue.global(qos: .utility).async {
                DispatchQueue.main.async {
                    expectation.fulfill()
                }
            }
        }
        wait(for: [expectation], timeout: 2)
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

        store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        waitForAsyncWrites()

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

        store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        waitForAsyncWrites()

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

        waitForAsyncWrites()
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

    func testHistoryCaptureDisabledPreventsPersistence() throws {
        let store = try makeStore()
        store.setHistoryCaptureEnabled(false)

        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))
        let block = TerminalBlockCapture(
            commandText: "echo hello",
            outputText: "hello",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            stage: .output
        )

        store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        waitForAsyncWrites()

        store.reloadRecentBlocks()
        XCTAssertTrue(store.recentBlocks.isEmpty)
    }

    func testClearHistoryRemovesSessionsAndBlocks() throws {
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

        store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)
        waitForAsyncWrites()
        store.reloadRecentBlocks()
        XCTAssertEqual(store.recentBlocks.count, 1)

        store.clearHistory()
        XCTAssertTrue(store.recentBlocks.isEmpty)
    }

    func testAsyncRecordBlockEventuallyReloads() throws {
        let store = try makeStore()
        let sessionID = store.startSession(shellPath: "/bin/zsh", workingDirectory: URL(fileURLWithPath: "/tmp"))

        let block = TerminalBlockCapture(
            commandText: "echo async",
            outputText: "async",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            stage: .output
        )

        store.recordBlock(sessionID: sessionID, block: block, orderIndex: 0)

        // recordBlock is now async — wait for background write + main-thread reload
        let expectation = XCTestExpectation(description: "async record and reload")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            store.reloadRecentBlocks()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(store.recentBlocks.count, 1)
        XCTAssertEqual(store.recentBlocks.first?.commandText, "echo async")
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

        waitForAsyncWrites()
        store.reloadRecentBlocks(limit: 2)
        XCTAssertEqual(store.recentBlocks.count, 2)
    }
}
