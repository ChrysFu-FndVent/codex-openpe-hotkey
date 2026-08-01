import Foundation

public struct EnhancementRequest: Encodable, Equatable {
    public let prompt: String
    public let client: String
    public let mode: String

    public init(prompt: String, client: String = "codex", mode: String = "agent") {
        self.prompt = prompt
        self.client = client
        self.mode = mode
    }
}

public struct EnhancementResponse: Decodable, Equatable {
    public let enhancedPrompt: String

    enum CodingKeys: String, CodingKey {
        case enhancedPrompt = "enhanced_prompt"
    }
}

public struct EnhancementErrorResponse: Decodable, Equatable {
    public let error: String?
    public let requestID: String?

    enum CodingKeys: String, CodingKey {
        case error
        case requestID = "request_id"
    }
}
