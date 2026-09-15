import Foundation

public struct ElevenLabsEngineClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias CredentialProvider = @Sendable (Int) -> SpeechCredentialStore.Credential

    private let transport: Transport
    private let credentialProvider: CredentialProvider

    public init(session: URLSession = .shared) {
        transport = { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw SpeechServiceError.invalidServiceResponse
            }
            return (data, response)
        }
        credentialProvider = {
            SpeechCredentialStore.load(provider: .elevenLabs, scope: $0)
        }
    }

    init(
        transport: @escaping Transport,
        credentialProvider: @escaping CredentialProvider
    ) {
        self.transport = transport
        self.credentialProvider = credentialProvider
    }

    public func voices(scope: Int) async throws -> [SpeechSynthesisVoice] {
        let apiKey = try apiKey(scope: scope)
        var result: [SpeechSynthesisVoice] = []
        var nextPageToken: String?
        var visitedTokens: Set<String> = []

        repeat {
            let url = try voicesURL(nextPageToken: nextPageToken)
            let (data, response) = try await transport(authenticatedRequest(url: url, apiKey: apiKey))
            try validate(response)
            let page: VoicesResponse
            do {
                page = try JSONDecoder().decode(VoicesResponse.self, from: data)
            } catch {
                throw SpeechServiceError.invalidServiceResponse
            }
            result.append(contentsOf: page.voices.map {
                SpeechSynthesisVoice(
                    identifier: $0.voiceID,
                    name: $0.name,
                    language: $0.verifiedLanguages?.map(\.language).joined(separator: ", ") ?? ""
                )
            })
            guard page.hasMore, let token = page.nextPageToken, !token.isEmpty,
                  visitedTokens.insert(token).inserted
            else {
                nextPageToken = nil
                break
            }
            nextPageToken = token
        } while nextPageToken != nil

        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Data() }
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(serviceURL)
        guard let voiceID = request.configuration.voiceIdentifier, !voiceID.isEmpty else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        guard let modelID = request.configuration.modelIdentifier, !modelID.isEmpty else {
            throw SpeechServiceError.invalidModelIdentifier
        }
        let apiKey = try apiKey(scope: request.scope)

        var url = serviceURL
        for component in ["text-to-speech", voiceID] {
            url.append(path: component, directoryHint: .notDirectory)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpeechServiceError.invalidServiceURL
        }
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        guard let synthesisURL = components.url else {
            throw SpeechServiceError.invalidServiceURL
        }
        var urlRequest = authenticatedRequest(url: synthesisURL, apiKey: apiKey)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = SynthesisRequestBody(
            text: text,
            modelID: modelID,
            voiceSettings: VoiceSettings(speed: min(2, max(0.5, Double(request.configuration.rate) / 0.5)))
        )
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }

        let (data, response) = try await transport(urlRequest)
        try validate(response)
        guard !data.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return data
    }

    private func voicesURL(nextPageToken: String?) throws -> URL {
        guard var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices") else {
            throw SpeechServiceError.invalidServiceURL
        }
        components.queryItems = [
            URLQueryItem(name: "page_size", value: "100"),
            URLQueryItem(name: "include_total_count", value: "false"),
            URLQueryItem(name: "sort", value: "name"),
            URLQueryItem(name: "sort_direction", value: "asc")
        ]
        if let nextPageToken {
            components.queryItems?.append(URLQueryItem(name: "next_page_token", value: nextPageToken))
        }
        guard let url = components.url else {
            throw SpeechServiceError.invalidServiceURL
        }
        return url
    }

    private func authenticatedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        return request
    }

    private func apiKey(scope: Int) throws -> String {
        let apiKey = credentialProvider(scope).password
        guard !apiKey.isEmpty else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }
        return apiKey
    }

    private func validate(_ serviceURL: URL) throws {
        guard serviceURL.scheme?.lowercased() == "https",
              serviceURL.host?.lowercased() == "api.elevenlabs.io"
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private struct VoicesResponse: Decodable {
        let voices: [Voice]
        let hasMore: Bool
        let nextPageToken: String?

        enum CodingKeys: String, CodingKey {
            case voices
            case hasMore = "has_more"
            case nextPageToken = "next_page_token"
        }
    }

    private struct Voice: Decodable {
        let voiceID: String
        let name: String
        let verifiedLanguages: [VerifiedLanguage]?

        enum CodingKeys: String, CodingKey {
            case voiceID = "voice_id"
            case name
            case verifiedLanguages = "verified_languages"
        }
    }

    private struct VerifiedLanguage: Decodable {
        let language: String
    }

    private struct SynthesisRequestBody: Encodable {
        let text: String
        let modelID: String
        let voiceSettings: VoiceSettings

        enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
            case voiceSettings = "voice_settings"
        }
    }

    private struct VoiceSettings: Encodable {
        let speed: Double
    }
}

@MainActor
public final class ElevenLabsSpeechSynthesizer: SpeechSynthesizing {
    private let client: ElevenLabsEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: ElevenLabsEngineClient = ElevenLabsEngineClient()) {
        self.client = client
    }

    public func speak(_ request: SpeechSynthesisRequest) async throws {
        stop()
        try Task.checkCancellation()
        let task = Task { try await client.synthesize(request) }
        requestTask = task
        defer { requestTask = nil }
        let audio = try await task.value
        guard !audio.isEmpty else { return }
        try Task.checkCancellation()
        try await audioPlayer.play(audio, volume: request.configuration.volume)
    }

    public func stop() {
        requestTask?.cancel()
        requestTask = nil
        audioPlayer.stop()
    }
}
