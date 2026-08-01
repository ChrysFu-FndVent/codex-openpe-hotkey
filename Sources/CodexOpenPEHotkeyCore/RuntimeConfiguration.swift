import Foundation

public struct RuntimeConfiguration: Equatable {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:18980/v1/prompt-enhance")!
    public static let defaultAllowedBundleIdentifiers = Set(["com.openai.codex"])

    public let endpoint: URL
    public let requestTimeout: TimeInterval
    public let allowedBundleIdentifiers: Set<String>
    public let keychainAccount: String
    public let serverTokenService: String
    public let progressLanguage: ProgressLanguage
    public let hotKeyShortcut: HotKeyShortcut

    public init(environment: [String: String], localeIdentifier: String, userName: String) throws {
        let endpointValue = environment["OPENPE_ENDPOINT"] ?? Self.defaultEndpoint.absoluteString
        guard let endpoint = URL(string: endpointValue),
              endpoint.scheme == "http" || endpoint.scheme == "https" else {
            throw ConfigurationError.invalidEndpoint(endpointValue)
        }

        let timeoutValue = environment["OPENPE_HOTKEY_TIMEOUT_SECONDS"] ?? "75"
        guard let requestTimeout = TimeInterval(timeoutValue), requestTimeout > 0 else {
            throw ConfigurationError.invalidTimeout(timeoutValue)
        }

        let bundleValue = environment["OPENPE_ALLOWED_BUNDLE_IDS"] ??
            Self.defaultAllowedBundleIdentifiers.sorted().joined(separator: ",")
        let allowedBundleIdentifiers = Set(
            bundleValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !allowedBundleIdentifiers.isEmpty else {
            throw ConfigurationError.noAllowedBundleIdentifiers
        }

        let languageValue = environment["OPENPE_PROGRESS_LANGUAGE"]?.lowercased()
        let progressLanguage: ProgressLanguage
        switch languageValue {
        case "zh", "zh-cn", "chinese":
            progressLanguage = .chinese
        case "en", "english":
            progressLanguage = .english
        default:
            progressLanguage = ProgressLanguage(localeIdentifier: localeIdentifier)
        }

        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
        self.allowedBundleIdentifiers = allowedBundleIdentifiers
        self.keychainAccount = environment["OPENPE_KEYCHAIN_ACCOUNT"] ?? userName
        self.serverTokenService = environment["OPENPE_SERVER_TOKEN_SERVICE"] ??
            "com.openpe.promptenhancer.server-token"
        self.progressLanguage = progressLanguage
        self.hotKeyShortcut = try HotKeyShortcut(
            environment["OPENPE_HOTKEY"] ?? HotKeyShortcut.defaultMacOS.displayName
        )
    }
}

public enum ConfigurationError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case invalidTimeout(String)
    case noAllowedBundleIdentifiers

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let value):
            return "Invalid OPENPE_ENDPOINT: \(value)"
        case .invalidTimeout(let value):
            return "Invalid OPENPE_HOTKEY_TIMEOUT_SECONDS: \(value)"
        case .noAllowedBundleIdentifiers:
            return "OPENPE_ALLOWED_BUNDLE_IDS must contain at least one bundle identifier"
        }
    }
}
