import Foundation

public struct HotKeyShortcut: Equatable {
    public enum Modifier: String, CaseIterable {
        case command
        case control
        case option
        case shift

        fileprivate var displayName: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    public static let defaultMacOS = try! HotKeyShortcut("option+q")

    public let modifiers: Set<Modifier>
    public let key: String

    public init(_ value: String) throws {
        let rawParts = value.split(separator: "+", omittingEmptySubsequences: false)
        let parts = rawParts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard parts.count >= 2, !parts.contains(where: { $0.isEmpty }) else {
            throw HotKeyShortcutError.invalidFormat(value)
        }

        var parsedModifiers = Set<Modifier>()
        var parsedKey: String?
        for part in parts {
            if let modifier = Self.parseModifier(part) {
                guard parsedModifiers.insert(modifier).inserted else {
                    throw HotKeyShortcutError.invalidFormat(value)
                }
            } else {
                guard parsedKey == nil, Self.isSupportedKey(part) else {
                    throw HotKeyShortcutError.invalidFormat(value)
                }
                parsedKey = part.uppercased()
            }
        }

        guard !parsedModifiers.isEmpty, let parsedKey else {
            throw HotKeyShortcutError.invalidFormat(value)
        }
        modifiers = parsedModifiers
        key = parsedKey
    }

    public var displayName: String {
        let orderedModifiers: [Modifier] = [.command, .control, .option, .shift]
        return (orderedModifiers.filter(modifiers.contains).map(\.displayName) + [key])
            .joined(separator: "+")
    }

    private static func parseModifier(_ value: String) -> Modifier? {
        switch value {
        case "cmd", "command": return .command
        case "ctrl", "control": return .control
        case "alt", "opt", "option": return .option
        case "shift": return .shift
        default: return nil
        }
    }

    private static func isSupportedKey(_ value: String) -> Bool {
        if value.count == 1, let scalar = value.unicodeScalars.first {
            return ("a"..."z").contains(Character(String(scalar))) ||
                ("0"..."9").contains(Character(String(scalar)))
        }
        if value.hasPrefix("f"), let number = Int(value.dropFirst()) {
            return (1...12).contains(number)
        }
        return false
    }
}

public enum HotKeyShortcutError: LocalizedError, Equatable {
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let value):
            return "Invalid hotkey '\(value)'. Use at least one modifier plus A-Z, 0-9, or F1-F12."
        }
    }
}
