import Foundation

public enum RealtimeProviderKind: String, Codable, CaseIterable, Sendable {
    case openAI
    case openAICompatible
}

public struct RealtimeAPIConfiguration: Sendable, Equatable {
    public let provider: RealtimeProviderKind
    public let baseURL: URL
    public let model: String
    public let voice: String
    public let apiKey: String

    public init(
        provider: RealtimeProviderKind,
        baseURL: URL,
        model: String,
        voice: String,
        apiKey: String
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.voice = voice
        self.apiKey = apiKey
    }

    public static func defaultBaseURL(for provider: RealtimeProviderKind) -> URL? {
        switch provider {
        case .openAI:
            URL(string: "https://api.openai.com")
        case .openAICompatible:
            nil
        }
    }
}

public struct RealtimeCall: Sendable, Equatable {
    public let answerSDP: String
    public let id: String?

    public init(answerSDP: String, id: String?) {
        self.answerSDP = answerSDP
        self.id = id
    }
}

public enum RealtimeAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Realtime APIキーが設定されていない。"
        case .invalidResponse:
            "Realtime APIから不正な応答を受信した。"
        case let .httpStatus(status, message):
            "Realtime APIエラー（HTTP \(status)）: \(message)"
        }
    }
}

public struct RealtimeAPIClient: Sendable {
    private let configuration: RealtimeAPIConfiguration
    private let session: URLSession

    public init(configuration: RealtimeAPIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func createCall(offerSDP: String) async throws -> RealtimeCall {
        guard !configuration.apiKey.isEmpty else { throw RealtimeAPIError.missingAPIKey }
        let requestData = try RealtimeCallRequestBuilder.make(
            baseURL: configuration.baseURL,
            model: configuration.model,
            voice: configuration.voice,
            offerSDP: offerSDP
        )
        var request = URLRequest(url: requestData.url)
        request.httpMethod = "POST"
        request.httpBody = requestData.body
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(requestData.contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RealtimeAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw RealtimeAPIError.httpStatus(
                http.statusCode,
                String(decoding: data.prefix(4096), as: UTF8.self)
            )
        }
        guard let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
            throw RealtimeAPIError.invalidResponse
        }
        let callID = http.value(forHTTPHeaderField: "X-Realtime-Session-ID")
            ?? Self.callID(fromLocation: http.value(forHTTPHeaderField: "Location"))
        return RealtimeCall(answerSDP: answer, id: callID)
    }

    public func hangup(callID: String) async throws {
        guard !configuration.apiKey.isEmpty else { throw RealtimeAPIError.missingAPIKey }
        let endpoint = RealtimeCallRequestBuilder.callsURL(baseURL: configuration.baseURL)
            .appending(path: callID)
            .appending(path: "hangup")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RealtimeAPIError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) || http.statusCode == 404 else {
            throw RealtimeAPIError.httpStatus(
                http.statusCode,
                String(decoding: data.prefix(4096), as: UTF8.self)
            )
        }
    }

    private static func callID(fromLocation location: String?) -> String? {
        guard let location, let component = location.split(separator: "/").last else { return nil }
        return String(component)
    }
}

public enum RealtimeCallRequestBuilder {
    public struct RequestData: Sendable, Equatable {
        public let url: URL
        public let contentType: String
        public let body: Data
    }

    public static func callsURL(baseURL: URL) -> URL {
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/v1/realtime/calls") || normalized.hasSuffix("/realtime/calls") {
            return URL(string: normalized)!
        }
        if normalized.hasSuffix("/v1") {
            return URL(string: normalized + "/realtime/calls")!
        }
        return URL(string: normalized + "/v1/realtime/calls")!
    }

    public static func make(
        baseURL: URL,
        model: String,
        voice: String,
        offerSDP: String,
        boundary: String = "UtataneRealtimeBoundary-\(UUID().uuidString)"
    ) throws -> RequestData {
        let session: [String: Any] = [
            "type": "realtime",
            "model": model,
            "audio": ["output": ["voice": voice]]
        ]
        let sessionData = try JSONSerialization.data(withJSONObject: session, options: [.sortedKeys])
        var body = Data()
        appendPart(name: "sdp", contentType: "application/sdp", data: Data(offerSDP.utf8), boundary: boundary, to: &body)
        appendPart(name: "session", contentType: "application/json", data: sessionData, boundary: boundary, to: &body)
        body.append(Data("--\(boundary)--\r\n".utf8))
        return RequestData(
            url: callsURL(baseURL: baseURL),
            contentType: "multipart/form-data; boundary=\(boundary)",
            body: body
        )
    }

    private static func appendPart(
        name: String,
        contentType: String,
        data: Data,
        boundary: String,
        to body: inout Data
    ) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }
}
