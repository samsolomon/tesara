import Darwin
import Dispatch
import Foundation

enum TerminalEvent {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

protocol TerminalProcessHandle {
    func send(_ input: String) throws
    func resize(cols: UInt16, rows: UInt16)
    func stop()
}

protocol TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle
}

enum TerminalLaunchError: LocalizedError {
    case invalidShellPath
    case invalidWorkingDirectory

    var errorDescription: String? {
        switch self {
        case .invalidShellPath:
            "The selected shell path is not executable."
        case .invalidWorkingDirectory:
            "The default working directory does not exist."
        }
    }
}

struct LocalShellLauncher: TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            throw TerminalLaunchError.invalidShellPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TerminalLaunchError.invalidWorkingDirectory
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-l"]
        process.currentDirectoryURL = workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onEvent(.stdout(text))
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            onEvent(.stderr(text))
        }

        process.terminationHandler = { process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            onEvent(.exit(process.terminationStatus))
        }

        try process.run()

        return LocalShellProcessHandle(
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting
        )
    }
}

private struct LocalShellProcessHandle: TerminalProcessHandle {
    let process: Process
    let stdinHandle: FileHandle

    func send(_ input: String) throws {
        guard let data = input.data(using: .utf8) else {
            return
        }
        try stdinHandle.write(contentsOf: data)
    }

    func stop() {
        if process.isRunning {
            process.terminate()
        }
        try? stdinHandle.close()
    }

    func resize(cols: UInt16, rows: UInt16) {}
}

final class PTYShellLauncher: TerminalLaunching {
    func launch(
        shellPath: String,
        workingDirectory: URL,
        onEvent: @escaping @Sendable (TerminalEvent) -> Void
    ) throws -> TerminalProcessHandle {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            throw TerminalLaunchError.invalidShellPath
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TerminalLaunchError.invalidWorkingDirectory
        }

        var masterFileDescriptor: Int32 = -1
        var windowSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&masterFileDescriptor, nil, nil, &windowSize)

        guard pid >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if pid == 0 {
            launchChildProcess(shellPath: shellPath, workingDirectory: workingDirectory)
        }

        return PTYShellProcessHandle(
            pid: pid,
            masterFileDescriptor: masterFileDescriptor,
            onEvent: onEvent
        )
    }

    private func launchChildProcess(shellPath: String, workingDirectory: URL) -> Never {
        _ = chdir(workingDirectory.path)
        setenv("TERM", "xterm-256color", 1)
        setenv("TERM_PROGRAM", "Tesara", 1)
        setenv("COLORTERM", "truecolor", 1)

        let loginShellName = "-" + URL(fileURLWithPath: shellPath).lastPathComponent

        shellPath.withCString { shellPathCString in
            loginShellName.withCString { loginShellCString in
                let arg0 = strdup(loginShellCString)
                defer { free(arg0) }

                var args: [UnsafeMutablePointer<CChar>?] = [arg0, nil]
                execv(shellPathCString, &args)
            }
        }

        perror("execv")
        _exit(127)
    }
}

private final class PTYShellProcessHandle: TerminalProcessHandle {
    private let pid: pid_t
    private let masterFileDescriptor: Int32
    private let onEvent: @Sendable (TerminalEvent) -> Void
    private let queue = DispatchQueue(label: "com.samsolomon.tesara.pty")
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var isStopped = false
    private var didHandleExit = false

    init(pid: pid_t, masterFileDescriptor: Int32, onEvent: @escaping @Sendable (TerminalEvent) -> Void) {
        self.pid = pid
        self.masterFileDescriptor = masterFileDescriptor
        self.onEvent = onEvent
        configureReadSource()
        configureProcessSource()
    }

    deinit {
        cleanup()
    }

    func send(_ input: String) throws {
        guard let data = input.data(using: .utf8) else {
            return
        }

        let result = data.withUnsafeBytes { buffer in
            Darwin.write(masterFileDescriptor, buffer.baseAddress, buffer.count)
        }

        guard result >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func stop() {
        queue.sync {
            guard !isStopped, !didHandleExit else {
                return
            }

            isStopped = true
            kill(pid, SIGTERM)

            var status: Int32 = 0
            if waitpid(pid, &status, 0) == pid {
                finishExit(status: status, shouldNotify: false)
            }
        }
    }

    func resize(cols: UInt16, rows: UInt16) {
        queue.async {
            guard !self.isStopped, !self.didHandleExit else {
                return
            }

            var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
            _ = withUnsafeMutablePointer(to: &size) {
                ioctl(self.masterFileDescriptor, TIOCSWINSZ, $0)
            }
            kill(self.pid, SIGWINCH)
        }
    }

    private func configureReadSource() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainReadableData()
        }
        source.setCancelHandler { [masterFileDescriptor] in
            Darwin.close(masterFileDescriptor)
        }
        readSource = source
        source.resume()
    }

    private func configureProcessSource() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            guard waitpid(self.pid, &status, 0) == self.pid else {
                return
            }
            self.finishExit(status: status, shouldNotify: true)
        }
        processSource = source
        source.resume()
    }

    private func drainReadableData() {
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(masterFileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer.prefix(Int(bytesRead)))
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    onEvent(.stdout(text))
                }
                continue
            }

            if bytesRead == 0 {
                cleanupReadSource()
            }

            break
        }
    }

    private func finishExit(status: Int32, shouldNotify: Bool) {
        guard !didHandleExit else {
            return
        }

        didHandleExit = true

        if shouldNotify {
            onEvent(.exit(Self.exitCode(from: status)))
        }

        cleanup()
    }

    private func cleanupReadSource() {
        readSource?.cancel()
        readSource = nil
    }

    private func cleanup() {
        cleanupReadSource()
        processSource?.cancel()
        processSource = nil
    }

    private static func exitCode(from status: Int32) -> Int32 {
        let terminationSignal = status & 0x7f

        if terminationSignal == 0 {
            return (status >> 8) & 0xff
        }

        if terminationSignal != 0x7f {
            return 128 + terminationSignal
        }

        return status
    }
}
