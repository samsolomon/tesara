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
    @Published private(set) var totalBlockCount: Int = 0
    @Published private(set) var startupErrorMessage: String?

    private let dbQueue: DatabaseQueue?
    private let migrator: DatabaseMigrator
    private var historyCaptureEnabled = true
    private var pendingReloadWork: DispatchWorkItem?

    init() {
        migrator = BlockStore.makeMigrator()

        do {
            let dbPath = try BlockStore.databasePath()
            let dbQueue = try DatabaseQueue(path: dbPath)
            try migrator.migrate(dbQueue)
            self.dbQueue = dbQueue
            // Restrict database file permissions — WAL/SHM are protected by the 0700 directory
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbPath)
            reloadRecentBlocks()
        } catch {
            self.dbQueue = nil
            startupErrorMessage = "History is unavailable: \(error.localizedDescription)"
            recentBlocks = []
        }
    }

    init(dbQueue: DatabaseQueue) throws {
        migrator = BlockStore.makeMigrator()
        try migrator.migrate(dbQueue)
        self.dbQueue = dbQueue
    }

    func startSession(shellPath: String, workingDirectory: URL) -> UUID {
        let sessionID = UUID()
        guard historyCaptureEnabled, let dbQueue else {
            return sessionID
        }

        let path = workingDirectory.path
        let startedAt = Date()
        DispatchQueue.global(qos: .utility).async {
            try? dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO terminal_sessions (id, shellPath, workingDirectory, startedAt)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [sessionID.uuidString, shellPath, path, startedAt]
                )
            }
        }

        return sessionID
    }

    func recordBlock(sessionID: UUID, block: TerminalBlockCapture, orderIndex: Int) {
        guard historyCaptureEnabled else { return }
        guard !block.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let dbQueue else { return }

        let blockID = UUID().uuidString
        let sessionIDString = sessionID.uuidString
        let commandText = block.commandText
        let outputText = block.outputText
        let exitCode = block.exitCode
        let startedAt = block.startedAt
        let finishedAt = block.finishedAt

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let didInsert = (try? dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO terminal_blocks (
                        id, sessionID, orderIndex, commandText, outputText, exitCode, startedAt, finishedAt
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        blockID,
                        sessionIDString,
                        orderIndex,
                        commandText,
                        outputText,
                        exitCode,
                        startedAt,
                        finishedAt
                    ]
                )
                return true
            }) ?? false

            if didInsert {
                DispatchQueue.main.async {
                    self?.scheduleReload()
                }
            }
        }
    }

    func setHistoryCaptureEnabled(_ enabled: Bool) {
        historyCaptureEnabled = enabled
    }

    func clearHistory() {
        guard let dbQueue else {
            recentBlocks = []
            return
        }

        try? dbQueue.write { db in
            try db.execute(sql: "DELETE FROM terminal_blocks")
            try db.execute(sql: "DELETE FROM terminal_sessions")
        }

        reloadRecentBlocks()
    }

    /// Debounced reload — coalesces multiple rapid inserts into a single query.
    private func scheduleReload() {
        pendingReloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadRecentBlocks()
        }
        pendingReloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    func reloadRecentBlocks(limit: Int = 100) {
        guard let dbQueue else {
            recentBlocks = []
            totalBlockCount = 0
            return
        }

        let result = try? dbQueue.read { db -> ([TerminalBlockSummary], Int) in
            let blocks = try TerminalBlockSummary.fetchAll(
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
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM terminal_blocks") ?? 0
            return (blocks, count)
        }
        recentBlocks = result?.0 ?? []
        totalBlockCount = result?.1 ?? 0
    }

    // MARK: - History Queries

    func recentCommandTexts(limit: Int = 500) -> [String] {
        guard let dbQueue else { return [] }
        return (try? dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT commandText
                FROM terminal_blocks
                ORDER BY startedAt DESC
                LIMIT ?
                """,
                arguments: [limit]
            )
        }) ?? []
    }

    func searchCommands(query: String, limit: Int = 50) -> [String] {
        guard let dbQueue else { return [] }
        let words = query.split(separator: " ").map { String($0) }
        guard !words.isEmpty else { return [] }

        var conditions: [String] = []
        var args: [String] = []
        for word in words {
            conditions.append("commandText LIKE ?")
            args.append("%\(word)%")
        }

        let whereClause = conditions.joined(separator: " AND ")
        return (try? dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT commandText
                FROM terminal_blocks
                WHERE \(whereClause)
                ORDER BY startedAt DESC
                LIMIT ?
                """,
                arguments: StatementArguments(args + [String(limit)])!
            )
        }) ?? []
    }

    private static func databasePath() throws -> String {
        let fileManager = FileManager.default
        let appSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupportDirectory.appendingPathComponent("Tesara", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
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
