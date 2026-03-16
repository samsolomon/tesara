import Foundation

/// Gathers diagnostic files into a temporary directory for sharing.
enum DiagnosticExport {
    /// Assembles logs, crash reports, config, and system info into a temp directory.
    /// Returns the URL to the directory, or nil if assembly fails.
    static func gather() -> URL? {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TesaraDiagnostics-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let fm = FileManager.default
        let logStore = LocalLogStore.shared

        // Copy files that may or may not exist — try directly, skip on failure
        try? fm.copyItem(at: logStore.logFileURL, to: exportDir.appendingPathComponent("Tesara.log"))
        try? fm.copyItem(at: logStore.rotatedLogFileURL, to: exportDir.appendingPathComponent("Tesara.log.1"))
        try? fm.copyItem(at: CrashHandler.logFileURL, to: exportDir.appendingPathComponent("last-crash.log"))

        let configURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/tesara/config")
        try? fm.copyItem(at: configURL, to: exportDir.appendingPathComponent("config"))

        // System info
        let systemInfo = buildSystemInfo()
        try? systemInfo.write(
            to: exportDir.appendingPathComponent("system-info.txt"),
            atomically: true,
            encoding: .utf8
        )

        return exportDir
    }

    private static func buildSystemInfo() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let arch = machineArchitecture()
        let model = hardwareModel()
        let ram = ProcessInfo.processInfo.physicalMemory
        let ramGB = String(format: "%.1f", Double(ram) / (1024 * 1024 * 1024))

        return """
        Tesara \(version) (\(build))
        macOS \(osVersion)
        Hardware: \(model)
        Architecture: \(arch)
        Physical RAM: \(ramGB) GB
        """
    }

    private static func machineArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
