import Foundation

public enum ProgressLanguage: Equatable {
    case chinese
    case english

    public init(localeIdentifier: String) {
        self = localeIdentifier.lowercased().hasPrefix("zh") ? .chinese : .english
    }
}

public struct ProgressIndicator: Equatable {
    public static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    public let elapsedSeconds: Int
    public let frameIndex: Int
    public let language: ProgressLanguage

    public init(elapsedSeconds: Int, frameIndex: Int, language: ProgressLanguage) {
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.frameIndex = max(0, frameIndex)
        self.language = language
    }

    public var text: String {
        let frame = Self.frames[frameIndex % Self.frames.count]
        return "[OpenPE \(frame)] \(message) \(elapsedSeconds)s"
    }

    private var message: String {
        switch (language, elapsedSeconds) {
        case (.chinese, 0..<15):
            return "正在优化"
        case (.chinese, 15..<45):
            return "仍在生成"
        case (.chinese, _):
            return "网络较慢"
        case (.english, 0..<15):
            return "Optimizing"
        case (.english, 15..<45):
            return "Still generating"
        case (.english, _):
            return "Network is slow"
        }
    }
}
