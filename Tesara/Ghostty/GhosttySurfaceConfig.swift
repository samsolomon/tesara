import AppKit

/// Configuration for creating a ghostty surface, including shell integration
/// environment variables, working directory, and command overrides.
///
/// The `withCValue(view:)` method converts this to a `ghostty_surface_config_s`
/// with proper C string lifetime management.
struct GhosttySurfaceConfig {
    var workingDirectory: String?
    var command: String?
    var envVars: [String: String] = [:]
    var fontSize: Float = 0
    var context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW

    /// Temporary files that must persist for the shell's entire lifetime.
    /// Cleaned up by the session/surface on destruction.
    var temporaryURLs: [URL] = []

    // MARK: - Shell Integration Setup

    /// Creates a surface config with Tesara's shell integration scripts injected.
    static func withShellIntegration(
        shellPath: String,
        workingDirectory: URL,
        sessionID: String = UUID().uuidString,
        fontSize: Float = 0,
        context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW
    ) -> GhosttySurfaceConfig {
        var config = GhosttySurfaceConfig()
        config.workingDirectory = workingDirectory.path
        config.fontSize = fontSize
        config.context = context

        // Common env vars
        config.envVars["TERM_PROGRAM"] = "Tesara"
        config.envVars["COLORTERM"] = "truecolor"
        config.envVars["TESARA_SESSION_ID"] = sessionID
        // Ensure shell scripts write temp files to the same directory Swift reads from
        config.envVars["TESARA_TMPDIR"] = NSTemporaryDirectory()

        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent

        switch shellName {
        case "zsh":
            configureZsh(config: &config)
        case "bash":
            configureBash(config: &config, shellPath: shellPath)
        case "fish":
            configureFish(config: &config)
        default:
            break
        }

        return config
    }

    // MARK: - Shell-Specific Configuration

    private static func configureZsh(config: inout GhosttySurfaceConfig) {
        guard let integrationURL = Bundle.main.url(
            forResource: "tesara-zsh-integration",
            withExtension: "zsh",
            subdirectory: "TerminalIntegration"
        ) else { return }

        let dotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-zsh-\(UUID().uuidString)", isDirectory: true)

        do {
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
            // Use single quotes around the integration path to prevent $, backtick expansion
            try writeFile(named: ".zshrc", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zshrc\" ]; then
              source \"$HOME/.zshrc\"
            fi
            if [ -f '\(integrationURL.path)' ]; then
              source '\(integrationURL.path)'
            fi
            """)
            try writeFile(named: ".zlogin", in: dotDirectory, contents: """
            if [ -f \"$HOME/.zlogin\" ]; then
              source \"$HOME/.zlogin\"
            fi
            """)

            config.envVars["ZDOTDIR"] = dotDirectory.path
            config.temporaryURLs.append(dotDirectory)
        } catch {
            print("[GhosttySurfaceConfig] Failed to set up zsh integration: \(error)")
        }
    }

    private static func configureBash(config: inout GhosttySurfaceConfig, shellPath: String) {
        guard let integrationURL = Bundle.main.url(
            forResource: "tesara-bash-integration",
            withExtension: "sh",
            subdirectory: "TerminalIntegration"
        ) else { return }

        let rcFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-bash-\(UUID().uuidString).sh")

        do {
            try """
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
            if [ -f '\(integrationURL.path)' ]; then
              source '\(integrationURL.path)'
            fi
            __tesara_existing_exit_trap=$(trap -p EXIT)
            __tesara_run_logout() {
              if [ -f "$HOME/.bash_logout" ]; then
                source "$HOME/.bash_logout"
              fi
            }
            if [ -n "$__tesara_existing_exit_trap" ]; then
              __tesara_existing_exit_handler=${__tesara_existing_exit_trap#trap -- ' }
              __tesara_existing_exit_handler=${__tesara_existing_exit_handler%' EXIT}
              trap "__tesara_run_logout; ${__tesara_existing_exit_handler}" EXIT
            else
              trap '__tesara_run_logout' EXIT
            fi
            """.write(to: rcFileURL, atomically: true, encoding: .utf8)

            // ghostty's `command` field is used to launch the shell with --rcfile
            // Quote the path to handle spaces in temp directory paths
            config.command = "\(shellPath) --rcfile '\(rcFileURL.path)' -i"
            config.temporaryURLs.append(rcFileURL)
        } catch {
            print("[GhosttySurfaceConfig] Failed to set up bash integration: \(error)")
        }
    }

    private static func configureFish(config: inout GhosttySurfaceConfig) {
        guard let integrationURL = Bundle.main.url(
            forResource: "tesara-fish-integration",
            withExtension: "fish",
            subdirectory: "TerminalIntegration"
        ) else { return }

        let confDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tesara-fish-\(UUID().uuidString)", isDirectory: true)
        let confDDir = confDir
            .appendingPathComponent("fish")
            .appendingPathComponent("conf.d", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: confDDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: integrationURL,
                to: confDDir.appendingPathComponent("tesara-fish-integration.fish")
            )

            if let existing = ProcessInfo.processInfo.environment["XDG_CONFIG_DIRS"] {
                config.envVars["XDG_CONFIG_DIRS"] = confDir.path + ":" + existing
            } else {
                config.envVars["XDG_CONFIG_DIRS"] = confDir.path
            }
            config.temporaryURLs.append(confDir)
        } catch {
            print("[GhosttySurfaceConfig] Failed to set up fish integration: \(error)")
        }
    }

    // MARK: - C Value Conversion

    /// Provides a C-compatible `ghostty_surface_config_s` within a closure.
    /// All C string pointers are only valid within the closure.
    func withCValue<T>(view: NSView, _ body: (inout ghostty_surface_config_s) throws -> T) rethrows -> T {
        var config = ghostty_surface_config_new()
        config.userdata = Unmanaged.passUnretained(view).toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(view).toOpaque()
        ))
        config.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2.0)
        config.font_size = fontSize
        config.wait_after_command = false
        config.context = context

        return try workingDirectory.withCString { cWorkingDir in
            config.working_directory = cWorkingDir

            return try command.withCString { cCommand in
                config.command = cCommand

                // Convert env vars dict to C arrays
                let keys = Array(envVars.keys)
                let values = Array(envVars.values)

                return try keys.withCStrings { keyCStrings in
                    return try values.withCStrings { valueCStrings in
                        var cEnvVars = [ghostty_env_var_s]()
                        cEnvVars.reserveCapacity(envVars.count)
                        for i in 0..<envVars.count {
                            cEnvVars.append(ghostty_env_var_s(
                                key: keyCStrings[i],
                                value: valueCStrings[i]
                            ))
                        }

                        return try cEnvVars.withUnsafeMutableBufferPointer { buffer in
                            config.env_vars = buffer.baseAddress
                            config.env_var_count = envVars.count
                            return try body(&config)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func writeFile(named name: String, in directory: URL, contents: String) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}
