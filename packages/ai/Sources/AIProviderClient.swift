import Foundation

public protocol AIProviderClient: Sendable {
    func respond(
        systemPrompt: String,
        history: [AIConversationMessage],
        input: AIPersonalityInput
    ) async throws -> AIPersonalityOutput
}

public struct AIConversationMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public enum AIProviderError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "AIのAPIキーが設定されていない。"
        case .invalidResponse: "AIから解釈できない応答が返った。"
        case let .httpStatus(status, message): "AI APIエラー (HTTP \(status)): \(message)"
        }
    }
}

public enum AIProviderClientFactory {
    public static func make(
        configuration: AIProviderConfiguration,
        session: URLSession = .shared
    ) -> any AIProviderClient {
        switch configuration.kind {
        case .openAI:
            OpenAIResponsesClient(configuration: configuration, session: session)
        case .openAICompatible:
            OpenAICompatibleClient(configuration: configuration, session: session)
        case .anthropic:
            AnthropicMessagesClient(configuration: configuration, session: session)
        case .gemini:
            GeminiClient(configuration: configuration, session: session)
        }
    }
}

struct JSONValue: Codable, Sendable {
    let speech: AIPersonalityOutput.Speech?
}

enum AIJSON {
    static let instruction = """
    Return only JSON matching this shape: {"speech":{"text":"...","surface":0}}.
    Use {"speech":null} when the ghost should not react. Do not emit SakuraScript or commands.
    """

    static func input(_ value: AIPersonalityInput) throws -> String {
        try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    }

    static func decode(_ text: String) throws -> AIPersonalityOutput {
        guard let data = text.data(using: .utf8) else { throw AIProviderError.invalidResponse }
        do {
            return try JSONDecoder().decode(AIPersonalityOutput.self, from: data)
        } catch {
            throw AIProviderError.invalidResponse
        }
    }
}

extension URLSession {
    func aiJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AIProviderError.httpStatus(
                http.statusCode,
                String(decoding: data.prefix(1000), as: UTF8.self)
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        return json
    }
}
