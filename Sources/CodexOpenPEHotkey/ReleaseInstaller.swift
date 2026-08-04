import AppKit
import ApplicationServices
import CodexOpenPEHotkeyCore
import Darwin
import Foundation

struct SetupConfiguration {
    let apiKey: String
    let baseURL: String
    let model: String
    let language: String
    let progressLanguage: String
    let hotKey: String
}

struct SetupResult {
    let hotKeyDisplayName: String
    let pluginInstalled: Bool
    let serverHealthy: Bool
}

enum ReleaseInstaller {
    static let releaseVersion = "0.4.0"
    static let apiKeyService = "com.openpe.promptenhancer.api-key"
    static let serverTokenService = "com.openpe.promptenhancer.server-token"

    private static let fileManager = FileManager.default
    private static let marketplaceName = "codex-openpe-hotkey"
    private static let pluginSelector = "codex-openpe-hotkey@codex-openpe-hotkey"

    static var isPackagedRelease: Bool {
        bundledOpenPEServer != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var requiresSetup: Bool {
        !fileManager.fileExists(atPath: configurationFile.path) ||
            !fileManager.fileExists(atPath: installationMarker.path) ||
            KeychainStore.string(service: apiKeyService, account: NSUserName()) == nil ||
            KeychainStore.string(service: serverTokenService, account: NSUserName()) == nil
    }

    static func relaunchFromInstalledLocationIfNeeded() throws -> Bool {
        let currentBundle = Bundle.main.bundleURL.standardizedFileURL
        let path = currentBundle.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(homeApplicationsDirectory.path + "/") {
            return false
        }
        guard path.hasPrefix("/Volumes/") || path.contains("AppTranslocation") else {
            return false
        }

        try fileManager.createDirectory(
            at: homeApplicationsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        if fileManager.fileExists(atPath: installedBundleURL.path) {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: installedBundleURL, resultingItemURL: &resultingURL)
        }
        try fileManager.copyItem(at: currentBundle, to: installedBundleURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", installedBundleURL.path, "--args", "--setup"]
        try process.run()
        return true
    }

    static func install(
        configuration: SetupConfiguration,
        progress: @escaping (String) -> Void
    ) throws -> SetupResult {
        guard let serverBinary = bundledOpenPEServer,
              fileManager.isExecutableFile(atPath: serverBinary.path) else {
            throw ReleaseInstallerError.bundledServerMissing
        }
        let shortcut = try HotKeyShortcut(configuration.hotKey)
        guard let baseURL = URL(string: configuration.baseURL),
              baseURL.scheme == "https" || baseURL.scheme == "http" else {
            throw ReleaseInstallerError.invalidBaseURL
        }
        guard !configuration.apiKey.isEmpty, !configuration.model.isEmpty else {
            throw ReleaseInstallerError.missingRequiredValue
        }

        progress("Saving credentials securely...")
        let account = NSUserName()
        try KeychainStore.set(configuration.apiKey, service: apiKeyService, account: account)
        let serverToken = try KeychainStore.randomToken()
        try KeychainStore.set(serverToken, service: serverTokenService, account: account)

        progress("Writing local configuration...")
        try writeConfiguration(configuration)
        try installRuntimeFiles(
            serverBinary: serverBinary,
            hotKey: shortcut.displayName,
            progressLanguage: configuration.progressLanguage
        )

        progress("Installing the Codex Plugin and Skill...")
        let pluginInstalled = try installCodexPlugin()

        progress("Starting background services...")
        try bootstrapLaunchAgents()
        let serverHealthy = waitForServerHealth()
        guard serverHealthy else { throw ReleaseInstallerError.serverHealthCheckFailed }
        try writeInstallationMarker()

        return SetupResult(
            hotKeyDisplayName: shortcut.displayName,
            pluginInstalled: pluginInstalled,
            serverHealthy: serverHealthy
        )
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static var homeApplicationsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    private static var installedBundleURL: URL {
        homeApplicationsDirectory.appendingPathComponent("OpenPE Hotkey.app", isDirectory: true)
    }

    private static var supportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexOpenPEHotkey", isDirectory: true)
    }

    private static var logsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
    }

    private static var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var configurationFile: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/openpe/.env", isDirectory: false)
    }

    private static var installationMarker: URL {
        supportDirectory.appendingPathComponent("installed-version")
    }

    private static var bundledOpenPEServer: URL? {
        Bundle.main.url(forResource: "openpe-server", withExtension: nil)
    }

    private static func writeConfiguration(_ configuration: SetupConfiguration) throws {
        let directory = configurationFile.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o700
        ])
        let systemPrompt = "Rewrite the user request as a concise, actionable instruction for a coding agent. Preserve intent, facts, constraints, and language. Do not invent requirements. Output only the rewritten instruction."
        let values = [
            "OPENPE_BASE_URL=\(configuration.baseURL)",
            "OPENPE_MODEL=\(configuration.model)",
            "OPENPE_LANGUAGE=\(configuration.language)",
            "OPENPE_TIMEOUT=60s",
            "OPENPE_SYSTEM_PROMPT=\"\(escapeEnvironmentValue(systemPrompt))\""
        ]
        try (values.joined(separator: "\n") + "\n").write(
            to: configurationFile,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationFile.path)
    }

    private static func writeInstallationMarker() throws {
        try (releaseVersion + "\n").write(
            to: installationMarker,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: installationMarker.path
        )
    }

    private static func installRuntimeFiles(
        serverBinary: URL,
        hotKey: String,
        progressLanguage: String
    ) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        guard let launcherSource = Bundle.main.url(
            forResource: "openpe-server-launcher",
            withExtension: "sh"
        ) else {
            throw ReleaseInstallerError.bundledLauncherMissing
        }
        let launcher = supportDirectory.appendingPathComponent("openpe-server-launcher")
        if fileManager.fileExists(atPath: launcher.path) { try fileManager.removeItem(at: launcher) }
        try fileManager.copyItem(at: launcherSource, to: launcher)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        let runtimeFile = supportDirectory.appendingPathComponent("runtime.env")
        let runtime = [
            "OPENPE_SERVER_BIN=\(shellQuote(serverBinary.path))",
            "OPENPE_ENV_FILE=\(shellQuote(configurationFile.path))",
            "OPENPE_LISTEN_ADDR=127.0.0.1:18980"
        ].joined(separator: "\n") + "\n"
        try runtime.write(to: runtimeFile, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: runtimeFile.path)

        let executable = Bundle.main.executableURL?.path ?? ""
        guard !executable.isEmpty else { throw ReleaseInstallerError.bundleExecutableMissing }
        let serverPlist: [String: Any] = [
            "Label": "com.openpe.promptenhancer.server",
            "ProgramArguments": [launcher.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": logsDirectory.appendingPathComponent("openpe-server.log").path,
            "StandardErrorPath": logsDirectory.appendingPathComponent("openpe-server-error.log").path
        ]
        let hotKeyPlist: [String: Any] = [
            "Label": "com.openpe.promptenhancer.hotkey",
            "ProgramArguments": [executable],
            "EnvironmentVariables": [
                "OPENPE_ALLOWED_BUNDLE_IDS": "com.openai.codex",
                "OPENPE_ENDPOINT": "http://127.0.0.1:18980/v1/prompt-enhance",
                "OPENPE_HOTKEY_TIMEOUT_SECONDS": "75",
                "OPENPE_HOTKEY": hotKey,
                "OPENPE_PROGRESS_LANGUAGE": progressLanguage
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logsDirectory.appendingPathComponent("openpe-hotkey.log").path,
            "StandardErrorPath": logsDirectory.appendingPathComponent("openpe-hotkey-error.log").path
        ]
        try writePlist(serverPlist, named: "com.openpe.promptenhancer.server.plist")
        try writePlist(hotKeyPlist, named: "com.openpe.promptenhancer.hotkey.plist")
    }

    private static func writePlist(_ value: [String: Any], named name: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: value,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentsDirectory.appendingPathComponent(name), options: .atomic)
    }

    private static func installCodexPlugin() throws -> Bool {
        guard let codex = locateCodexCLI() else { throw ReleaseInstallerError.codexCLIMissing }
        guard let marketplace = Bundle.main.url(
            forResource: "CodexPlugin",
            withExtension: nil
        ) else {
            throw ReleaseInstallerError.bundledPluginMissing
        }
        let list = try run(codex, ["plugin", "marketplace", "list", "--json"])
        let marketplaceExists = list.output.contains("\"name\": \"\(marketplaceName)\"") ||
            list.output.contains("\"name\":\"\(marketplaceName)\"")
        if marketplaceExists {
            _ = try? run(codex, ["plugin", "marketplace", "remove", marketplaceName, "--json"])
        }
        _ = try run(codex, ["plugin", "marketplace", "add", marketplace.path, "--json"])

        let addResult = try? run(codex, ["plugin", "add", pluginSelector, "--json"])
        if addResult == nil {
            let installed = try run(codex, ["plugin", "list", "--json"])
            guard installed.output.contains("\"pluginId\": \"\(pluginSelector)\"") ||
                    installed.output.contains("\"pluginId\":\"\(pluginSelector)\"") else {
                throw ReleaseInstallerError.pluginInstallationFailed
            }
        }
        return true
    }

    private static func locateCodexCLI() -> URL? {
        var candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex").path,
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/plugins/.plugin-appserver/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        candidates.append(contentsOf: pathEntries.map { "\($0)/codex" })
        return candidates.lazy
            .map(URL.init(fileURLWithPath:))
            .first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private static func bootstrapLaunchAgents() throws {
        let domain = "gui/\(getuid())"
        for label in ["com.openpe.promptenhancer.hotkey", "com.openpe.promptenhancer.server"] {
            _ = try? run(URL(fileURLWithPath: "/bin/launchctl"), ["bootout", "\(domain)/\(label)"])
        }
        for name in ["com.openpe.promptenhancer.server.plist", "com.openpe.promptenhancer.hotkey.plist"] {
            _ = try run(URL(fileURLWithPath: "/bin/launchctl"), [
                "bootstrap", domain, launchAgentsDirectory.appendingPathComponent(name).path
            ])
        }
    }

    private static func waitForServerHealth() -> Bool {
        for _ in 0..<12 {
            if let result = try? run(URL(fileURLWithPath: "/usr/bin/curl"), [
                "--fail", "--silent", "--show-error", "--max-time", "2",
                "http://127.0.0.1:18980/healthz"
            ]), result.status == 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    @discardableResult
    private static func run(_ executable: URL, _ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let standardOutput = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let standardError = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let result = ProcessResult(status: process.terminationStatus, output: standardOutput)
        guard result.status == 0 else {
            throw ReleaseInstallerError.commandFailed(
                executable.lastPathComponent,
                standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }

    private static func escapeEnvironmentValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct ProcessResult {
    let status: Int32
    let output: String
}

enum ReleaseInstallerError: LocalizedError {
    case bundledServerMissing
    case bundledLauncherMissing
    case bundledPluginMissing
    case bundleExecutableMissing
    case codexCLIMissing
    case invalidBaseURL
    case missingRequiredValue
    case pluginInstallationFailed
    case serverHealthCheckFailed
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .bundledServerMissing:
            return "The release does not contain the bundled openpe-server binary."
        case .bundledLauncherMissing:
            return "The release does not contain the openPE server launcher."
        case .bundledPluginMissing:
            return "The release does not contain the bundled Codex Plugin and Skill."
        case .bundleExecutableMissing:
            return "The installed application executable could not be resolved."
        case .codexCLIMissing:
            return "Codex desktop is required. Install or update Codex, then run setup again."
        case .invalidBaseURL:
            return "The API base URL must be an absolute HTTP or HTTPS URL."
        case .missingRequiredValue:
            return "API key and model are required."
        case .pluginInstallationFailed:
            return "The Codex Plugin could not be installed or verified."
        case .serverHealthCheckFailed:
            return "The bundled openPE server did not pass its local health check."
        case .commandFailed(let command, let message):
            return "\(command) failed: \(message.isEmpty ? "unknown error" : message)"
        }
    }
}
