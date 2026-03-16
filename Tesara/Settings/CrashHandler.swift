import Foundation

/// Pre-opened file descriptor for the signal handler (must be module-level for async-signal-safety).
private var crashLogFD: Int32 = -1

/// Pre-allocated backtrace buffer — must not heap-allocate inside a signal handler.
private var backtraceBuffer = [UnsafeMutableRawPointer?](repeating: nil, count: 128)

/// Installs crash handlers for debug diagnostics.
///
/// Catches both ObjC/Swift exceptions (via NSUncaughtExceptionHandler) and
/// POSIX signals (SIGSEGV, SIGBUS, SIGABRT, SIGFPE, SIGILL). Writes a
/// minimal crash report to `~/Library/Logs/Tesara/last-crash.log`.
enum CrashHandler {
    static let logFileURL: URL = {
        LocalLogStore.shared.directoryURL.appendingPathComponent("last-crash.log")
    }()

    static func install() {
        // Check for crash from previous session
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            LocalLogStore.shared.log("[CrashHandler] Previous session crash detected", level: .warn)
        }

        // Ensure log directory exists
        try? FileManager.default.createDirectory(
            at: LocalLogStore.shared.directoryURL,
            withIntermediateDirectories: true
        )

        // Pre-open crash file descriptor for signal handler.
        // Don't truncate here — the previous crash log must survive until
        // DiagnosticExport can copy it. Truncation happens in the handlers
        // right before they write a new report.
        crashLogFD = open(logFileURL.path, O_WRONLY | O_CREAT, 0o600)

        // Install ObjC/Swift exception handler
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)

        // Install POSIX signal handlers
        let signals: [Int32] = [SIGSEGV, SIGBUS, SIGABRT, SIGFPE, SIGILL]
        for sig in signals {
            var newAction = sigaction()
            newAction.__sigaction_u.__sa_handler = crashSignalHandler
            sigemptyset(&newAction.sa_mask)
            newAction.sa_flags = 0
            sigaction(sig, &newAction, nil)
        }
    }
}

private func uncaughtExceptionHandler(_ exception: NSException) {
    let name = exception.name.rawValue
    let reason = exception.reason ?? "(no reason)"
    let symbols = exception.callStackSymbols.joined(separator: "\n")
    let report = """
    Uncaught Exception: \(name)
    Reason: \(reason)

    Call Stack:
    \(symbols)
    """
    try? report.write(to: CrashHandler.logFileURL, atomically: true, encoding: .utf8)
}

private func writeFD(_ fd: Int32, _ s: StaticString) {
    s.withUTF8Buffer { buffer in
        _ = write(fd, buffer.baseAddress, buffer.count)
    }
}

private func crashSignalHandler(_ signal: Int32) {
    let fd = crashLogFD
    guard fd >= 0 else {
        Darwin.signal(signal, SIG_DFL)
        Darwin.raise(signal)
        return
    }

    // Truncate previous contents before writing new report (async-signal-safe)
    ftruncate(fd, 0)
    lseek(fd, 0, SEEK_SET)

    writeFD(fd, "Signal: ")

    let name: StaticString = switch signal {
    case SIGSEGV:  "SIGSEGV"
    case SIGBUS:   "SIGBUS"
    case SIGABRT:  "SIGABRT"
    case SIGFPE:   "SIGFPE"
    case SIGILL:   "SIGILL"
    default:       "UNKNOWN"
    }
    writeFD(fd, name)
    writeFD(fd, "\nBacktrace:\n")

    // Use pre-allocated buffer — heap allocation is not async-signal-safe
    let count = backtrace(&backtraceBuffer, Int32(backtraceBuffer.count))
    backtrace_symbols_fd(&backtraceBuffer, count, fd)

    close(fd)

    // Re-raise with default handler so the process terminates normally
    Darwin.signal(signal, SIG_DFL)
    Darwin.raise(signal)
}
