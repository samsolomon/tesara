import Foundation

final class LocalLogStore: @unchecked Sendable {
    static let shared = LocalLogStore()

    let directoryURL: URL

    private let queue = DispatchQueue(label: "com.tesara.local-log-store")
    private let fileManager: FileManager
    private let formatter = ISO8601DateFormatter()
    private let logFileName = "Tesara.log"
    private var isEnabled = true
    private var fileHandle: FileHandle?

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else if let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            self.directoryURL = libraryDirectory
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("Tesara", isDirectory: true)
        } else {
            self.directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("TesaraLogs", isDirectory: true)
        }
    }

    var logFileURL: URL {
        directoryURL.appendingPathComponent(logFileName)
    }

    var displayPath: String {
        directoryURL.path
    }

    func setEnabled(_ enabled: Bool) {
        queue.sync {
            isEnabled = enabled
            if !enabled {
                closeHandle()
            }
        }
    }

    /// Maximum log file size before rotation (5 MB).
    private let maxLogSize: UInt64 = 5 * 1024 * 1024

    private var rotatedLogFileURL: URL {
        directoryURL.appendingPathComponent(logFileName + ".1")
    }

    func log(_ message: String) {
        queue.async {
            guard self.isEnabled else { return }

            do {
                try self.fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)

                self.rotateIfNeeded()

                let timestamp = self.formatter.string(from: Date())
                let line = "[\(timestamp)] \(message)\n"
                let data = Data(line.utf8)

                if let handle = self.fileHandle {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else if self.fileManager.fileExists(atPath: self.logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: self.logFileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    self.fileHandle = handle
                } else {
                    try data.write(to: self.logFileURL, options: .atomic)
                    try? self.fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.logFileURL.path)
                    self.fileHandle = try? FileHandle(forWritingTo: self.logFileURL)
                    _ = self.fileHandle.map { try? $0.seekToEnd() }
                }
            } catch {
                print("[LocalLogStore] Failed to write log: \(error)")
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }
        closeHandle()
        try? fileManager.removeItem(at: rotatedLogFileURL)
        try? fileManager.moveItem(at: logFileURL, to: rotatedLogFileURL)
    }

    func clearLogs() {
        queue.sync {
            closeHandle()
            try? fileManager.removeItem(at: rotatedLogFileURL)
            guard fileManager.fileExists(atPath: directoryURL.path) else { return }
            try? fileManager.removeItem(at: directoryURL)
        }
    }

    private func closeHandle() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
