import XCTest
@testable import Tesara

final class GhosttySurfaceConfigTests: XCTestCase {

    // MARK: - Common Env Vars

    func testWithShellIntegrationSetsCommonEnvVars() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            sessionID: "test-session-123"
        )

        XCTAssertEqual(config.envVars["TERM_PROGRAM"], "Tesara")
        XCTAssertEqual(config.envVars["COLORTERM"], "truecolor")
        XCTAssertEqual(config.envVars["TESARA_SESSION_ID"], "test-session-123")
    }

    func testWithShellIntegrationSetsWorkingDirectory() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/Users/test")
        )

        XCTAssertEqual(config.workingDirectory, "/Users/test")
    }

    // MARK: - Zsh Configuration

    func testZshConfigSetsZDOTDIR() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertNotNil(config.envVars["ZDOTDIR"])
        XCTAssertNil(config.command, "zsh should not set a custom command")
    }

    func testZshConfigCreatesTemporaryFiles() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertFalse(config.temporaryURLs.isEmpty, "zsh config should register temp ZDOTDIR for cleanup")

        // Verify the temp directory was actually created
        guard let zdotdir = config.envVars["ZDOTDIR"] else {
            XCTFail("ZDOTDIR not set")
            return
        }

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: zdotdir, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify .zshrc exists and sources the integration script
        let zshrcPath = (zdotdir as NSString).appendingPathComponent(".zshrc")
        let zshrcContent = try? String(contentsOfFile: zshrcPath, encoding: .utf8)
        XCTAssertNotNil(zshrcContent)
        XCTAssertTrue(zshrcContent?.contains("tesara-zsh-integration") ?? false)

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Bash Configuration

    func testBashConfigSetsCommand() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/bash",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertNotNil(config.command, "bash config should set a custom command with --rcfile")
        if let command = config.command {
            XCTAssertTrue(command.contains("/bin/bash"), "Command should reference shell path")
            XCTAssertTrue(command.contains("--rcfile"), "Command should include --rcfile flag")
            XCTAssertTrue(command.contains("-i"), "Command should include -i flag")
        }

        XCTAssertNil(config.envVars["ZDOTDIR"], "bash should not set ZDOTDIR")

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testBashConfigCreatesRCFile() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/bash",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertFalse(config.temporaryURLs.isEmpty)

        // The RC file should contain integration source
        if let rcURL = config.temporaryURLs.first {
            let content = try? String(contentsOf: rcURL, encoding: .utf8)
            XCTAssertNotNil(content)
            XCTAssertTrue(content?.contains("tesara-bash-integration") ?? false)
        }

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Fish Configuration

    func testFishConfigSetsXDGConfigDirs() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/usr/local/bin/fish",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertNotNil(config.envVars["XDG_CONFIG_DIRS"], "fish config should set XDG_CONFIG_DIRS")
        XCTAssertNil(config.command, "fish should not set a custom command")
        XCTAssertNil(config.envVars["ZDOTDIR"], "fish should not set ZDOTDIR")

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testFishConfigCreatesConfDDirectory() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/usr/local/bin/fish",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertFalse(config.temporaryURLs.isEmpty)

        // Verify conf.d directory was created with integration script
        guard let xdgDirs = config.envVars["XDG_CONFIG_DIRS"] else {
            XCTFail("XDG_CONFIG_DIRS not set")
            return
        }

        let basePath = xdgDirs.components(separatedBy: ":").first ?? xdgDirs
        let confDPath = (basePath as NSString)
            .appendingPathComponent("fish")
            .appending("/conf.d")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: confDPath, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Unknown Shell

    func testUnknownShellSetsNoShellSpecificConfig() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/usr/bin/unknown-shell",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )

        // Should still have common env vars
        XCTAssertEqual(config.envVars["TERM_PROGRAM"], "Tesara")
        XCTAssertEqual(config.envVars["COLORTERM"], "truecolor")

        // But no shell-specific setup
        XCTAssertNil(config.envVars["ZDOTDIR"])
        XCTAssertNil(config.envVars["XDG_CONFIG_DIRS"])
        XCTAssertNil(config.command)
        XCTAssertTrue(config.temporaryURLs.isEmpty)
    }

    // MARK: - Defaults

    func testDefaultFontSizeIsZero() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(config.fontSize, 0)

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCustomFontSize() {
        let config = GhosttySurfaceConfig.withShellIntegration(
            shellPath: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            fontSize: 14.0
        )
        XCTAssertEqual(config.fontSize, 14.0)

        // Cleanup
        for url in config.temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
