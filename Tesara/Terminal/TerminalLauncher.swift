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

        let launchConfiguration = try shellLaunchConfiguration(for: shellPath)

        var masterFileDescriptor: Int32 = -1
        var windowSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&masterFileDescriptor, nil, nil, &windowSize)

        guard pid >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if pid == 0 {
            launchChildProcess(
                shellPath: shellPath,
                workingDirectory: workingDirectory,
                launchConfiguration: launchConfiguration
            )
        }

        return PTYShellProcessHandle(
            pid: pid,
            masterFileDescriptor: masterFileDescriptor,
            onEvent: onEvent,
            temporaryURLs: launchConfiguration.temporaryURLs
        )
    }

    private func shellLaunchConfiguration(for shellPath: String) throws -> ShellLaunchConfiguration {
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent

        if shellName == "zsh", let integrationURL = Bundle.main.url(forResource: "tesara-zsh-integration", withExtension: "zsh", subdirectory: "TerminalIntegration") {
            let dotDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tesara-zsh-\(UUID().uuidString)", isDirectory: true)

            try FileManager.default.createDirectory(at: dotDirectory, withIntermediateDirectories: true)

            try writeFile(named: ".zshenv", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zshenv\" ]; then
              source \"$HOME/.zshenv\"
            fi
            """)
            try writeFile(named: ".zprofile", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zprofile\" ]; then
              source \"$HOME/.zprofile\"
            fi
            """)
            try writeFile(named: ".zshrc", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zshrc\" ]; then
              source \"$HOME/.zshrc\"
            fi
            if [ -f \"\(integrationURL.path)\" ]; then
              source \"\(integrationURL.path)\"
            fi
            """)
            try writeFile(named: ".zlogin", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zlogin\" ]; then
              source \"$HOME/.zlogin\"
            fi
            """)

            return ShellLaunchConfiguration(
                arguments: ["-zsh"],
                environment: ["ZDOTDIR": dotDirectory.path],
                temporaryURLs: [dotDirectory]
            )
        }

        if shellName == "bash", let integrationURL = Bundle.main.url(forResource: "tesara-bash-integration", withExtension: "sh", subdirectory: "TerminalIntegration") {
            let rcFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("tesara-bash-\(UUID().uuidString).sh")

            try writeFile(at: rcFileURL, contents: """
            if [ -f /etc/profile ]; then
              source /etc/profile
            fi
            if [ -f "$HOME/.bash_profile" ]; then
              source "$HOME/.bash_profile"
            elif [ -f "$HOME/.bash_login" ]; then
              source "$HOME/.bash_login"
            elif [ -f "$HOME/.profile" ]; then
              source "$HOME/.profile"
            fi
            if [ -f "$HOME/.bashrc" ]; then
              source "$HOME/.bashrc"
            fi
            if [ -f "\(integrationURL.path)" ]; then
              source "\(integrationURL.path)"
            fi
            __tesara_existing_exit_trap=$(trap -p EXIT)
            __tesara_run_logout() {
              if [ -f "$HOME/.bash_logout" ]; then
                source "$HOME/.bash_logout"
              fi
            }
            if [ -n "$__tesara_existing_exit_trap" ]; then
              __tesara_existing_exit_handler=${__tesara_existing_exit_trap#trap -- \' }
              __tesara_existing_exit_handler=${__tesara_existing_exit_handler%\' EXIT}
              trap "__tesara_run_logout; ${__tesara_existing_exit_handler}" EXIT
            else
              trap '__tesara_run_logout' EXIT
            fi
            """)

            return ShellLaunchConfiguration(
                arguments: ["-bash", "--rcfile", rcFileURL.path, "-i"],
                environment: [:],
                temporaryURLs: [rcFileURL]
            )
        }

        if shellName == "fish", let integrationURL = Bundle.main.url(forResource: "tesara-fish-integration", withExtension: "fish", subdirectory: "TerminalIntegration") {
            let confDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tesara-fish-\(UUID().uuidString)", isDirectory: true)
            let confDDir = confDir.appendingPathComponent("fish").appendingPathComponent("conf.d", isDirectory: true)

            try FileManager.default.createDirectory(at: confDDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: integrationURL, to: confDDir.appendingPathComponent("tesara-fish-integration.fish"))

            var env: [String: String] = [:]
            if let existingConfigDirs = ProcessInfo.processInfo.environment["XDG_CONFIG_DIRS"] {
                env["XDG_CONFIG_DIRS"] = confDir.path + ":" + existingConfigDirs
            } else {
                env["XDG_CONFIG_DIRS"] = confDir.path
            }

            return ShellLaunchConfiguration(
                arguments: ["-fish"],
                environment: env,
                temporaryURLs: [confDir]
            )
        }

        return ShellLaunchConfiguration(arguments: ["-" + shellName], environment: [:])
    }

    private func writeFile(named name: String, in directory: URL, contents: String) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func writeFile(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func launchChildProcess(shellPath: String, workingDirectory: URL, launchConfiguration: ShellLaunchConfiguration) -> Never {
        _ = chdir(workingDirectory.path)
        setenv("TERM", "xterm-256color", 1)
        setenv("TERM_PROGRAM", "Tesara", 1)
        setenv("COLORTERM", "truecolor", 1)

        for (key, value) in launchConfiguration.environment {
            setenv(key, value, 1)
        }

        shellPath.withCString { shellPathCString in
            let pointers = launchConfiguration.arguments.map { strdup($0) }
            defer {
                for pointer in pointers {
                    free(pointer)
                }
            }

            var args = pointers + [nil]
            args.withUnsafeMutableBufferPointer { buffer in
                execv(shellPathCString, buffer.baseAddress)
            }
        }

        perror("execv")
        _exit(127)
    }
}

private struct ShellLaunchConfiguration {
    let arguments: [String]
    let environment: [String: String]
    var temporaryURLs: [URL] = []
}

private final class PTYShellProcessHandle: TerminalProcessHandle {
    private let pid: pid_t
    private let masterFileDescriptor: Int32
    private let onEvent: @Sendable (TerminalEvent) -> Void
    private let queue = DispatchQueue(label: "com.samsolomon.tesara.pty")
    private let temporaryURLs: [URL]
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var isStopped = false
    private var didHandleExit = false

    init(pid: pid_t, masterFileDescriptor: Int32, onEvent: @escaping @Sendable (TerminalEvent) -> Void, temporaryURLs: [URL] = []) {
        self.pid = pid
        self.masterFileDescriptor = masterFileDescriptor
        self.onEvent = onEvent
        self.temporaryURLs = temporaryURLs
        configureReadSource()
        configureProcessSource()
    }

    deinit {
        cleanup()
        cleanupTemporaryFiles()
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

    private func cleanupTemporaryFiles() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
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
