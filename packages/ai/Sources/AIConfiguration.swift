import Foundation

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case openAI
    case anthropic
    case gemini
    case openAICompatible
}

public struct AIProviderConfiguration: Sendable, Equatable {
    public let kind: AIProviderKind
    public let baseURL: URL?
    public let model: String
    public let apiKey: String
    public let timeoutSeconds: Double

    public init(
        kind: AIProviderKind,
        baseURL: URL? = nil,
        model: String,
        apiKey: String,
        timeoutSeconds: Double = 30
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AIGhostManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let prompt: String
    public let allowedSurfaces: [Int]
    public let fallbackSurface: Int
    public let fallbackText: String

    public init(
        version: Int = 1,
        prompt: String,
        allowedSurfaces: [Int],
        fallbackSurface: Int = 0,
        fallbackText: String = "今ちょっと考えられない。あとで。"
    ) {
        self.version = version
        self.prompt = prompt
        self.allowedSurfaces = allowedSurfaces
        self.fallbackSurface = fallbackSurface
        self.fallbackText = fallbackText
    }
}

public enum AIGhostManifestLoader {
    public static let filename = "ai.json"

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: masterDirectoryURL.appending(path: filename).path
        )
    }

    public static func load(masterDirectoryURL: URL) throws -> AIGhostManifest {
        let data = try Data(contentsOf: masterDirectoryURL.appending(path: filename))
        return try JSONDecoder().decode(AIGhostManifest.self, from: data)
    }
}
