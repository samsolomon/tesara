import Foundation
import GRDB

struct TerminalBlockSummary: Identifiable, FetchableRecord, Decodable {
    var id: String
    var sessionID: String
    var shellPath: String
    var workingDirectory: String
    var commandText: String
    var outputText: String
    var exitCode: Int?
    var startedAt: Date
    var finishedAt: Date
}

@MainActor
final class BlockStore: ObservableObject {
    @Published private(set) var recentBlocks: [TerminalBlockSummary] = []
    @Published private(set) var startupErrorMessage: String?

    private let dbQueue: DatabaseQueue?
    private let migrator: DatabaseMigrator

    init() {
        migrator = BlockStore.makeMigrator()

        do {
            let dbQueue = try DatabaseQueue(path: BlockStore.databasePath)
            try migrator.migrate(dbQueue)
            self.dbQueue = dbQueue
            reloadRecentBlocks()
        } catch {
            self.dbQueue = nil
            startupErrorMessage = "History is unavailable: \(error.localizedDescription)"
            recentBlocks = []
        }
    }

    func startSession(shellPath: String, workingDirectory: URL) -> UUID {
        let sessionID = UUID()
        guard let dbQueue else {
            return sessionID
        }

        try? dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO terminal_sessions (id, shellPath, workingDirectory, startedAt)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [sessionID.uuidString, shellPath, workingDirectory.path, Date()]
            )
        }

        return sessionID
    }

    @discardableResult
    func recordBlock(sessionID: UUID, block: TerminalBlockCapture, orderIndex: Int) -> Bool {
        guard !block.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        guard let dbQueue else {
            return false
        }

        let didInsert = (try? dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO terminal_blocks (
                    id, sessionID, orderIndex, commandText, outputText, exitCode, startedAt, finishedAt
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    sessionID.uuidString,
                    orderIndex,
                    block.commandText,
                    block.outputText,
                    block.exitCode,
                    block.startedAt,
                    block.finishedAt
                ]
            )
            return true
        }) ?? false

        if didInsert {
            reloadRecentBlocks()
        }

        return didInsert
    }

    func reloadRecentBlocks(limit: Int = 100) {
        guard let dbQueue else {
            recentBlocks = []
            return
        }

        recentBlocks = (try? dbQueue.read { db in
            try TerminalBlockSummary.fetchAll(
                db,
                sql: """
                SELECT
                    terminal_blocks.id,
                    terminal_blocks.sessionID,
                    terminal_sessions.shellPath,
                    terminal_sessions.workingDirectory,
                    terminal_blocks.commandText,
                    terminal_blocks.outputText,
                    terminal_blocks.exitCode,
                    terminal_blocks.startedAt,
                    terminal_blocks.finishedAt
                FROM terminal_blocks
                INNER JOIN terminal_sessions ON terminal_sessions.id = terminal_blocks.sessionID
                ORDER BY terminal_blocks.startedAt DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }) ?? []
    }

    private static var databasePath: String {
        let fileManager = FileManager.default
        let appSupportDirectory = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupportDirectory.appendingPathComponent("Tesara", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tesara.sqlite").path
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create-terminal-history") { db in
            try db.create(table: "terminal_sessions") { table in
                table.column("id", .text).primaryKey()
                table.column("shellPath", .text).notNull()
                table.column("workingDirectory", .text).notNull()
                table.column("startedAt", .datetime).notNull()
            }

            try db.create(table: "terminal_blocks") { table in
                table.column("id", .text).primaryKey()
                table.column("sessionID", .text).notNull().indexed().references("terminal_sessions", onDelete: .cascade)
                table.column("orderIndex", .integer).notNull()
                table.column("commandText", .text).notNull()
                table.column("outputText", .text).notNull()
                table.column("exitCode", .integer)
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime).notNull()
            }
        }

        return migrator
    }
}
