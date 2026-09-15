import Foundation

public struct OpenAISpeechEngineClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias CredentialProvider = @Sendable (
        SpeechSynthesisProvider,
        Int
    ) -> SpeechCredentialStore.Credential

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
        credentialProvider = { provider, scope in
            switch provider {
            case .openAI:
                SpeechCredentialStore.load(provider: .openAI, scope: scope)
            case .openAICompatibleLocal:
                SpeechCredentialStore.load(provider: .openAICompatibleLocal, scope: scope)
            default:
                SpeechCredentialStore.Credential()
            }
        }
    }

    init(
        transport: @escaping Transport,
        credentialProvider: @escaping CredentialProvider
    ) {
        self.transport = transport
        self.credentialProvider = credentialProvider
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Data() }
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(serviceURL: serviceURL, provider: request.configuration.provider)
        guard let model = request.configuration.modelIdentifier, !model.isEmpty else {
            throw SpeechServiceError.invalidModelIdentifier
        }
        guard let voice = request.configuration.voiceIdentifier, !voice.isEmpty else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let apiKey = credentialProvider(request.configuration.provider, request.scope).password
        if request.configuration.provider == .openAI, apiKey.isEmpty {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }

        var url = serviceURL
        for component in ["audio", "speech"] {
            url.append(path: component, directoryHint: .notDirectory)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = SynthesisRequestBody(
            model: model,
            input: text,
            voice: voice,
            instructions: request.configuration.instructions?.nilIfEmpty,
            responseFormat: "wav",
            speed: min(4, max(0.25, Double(request.configuration.rate) / 0.5))
        )
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }

        let (data, response) = try await transport(urlRequest)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
        guard !data.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return data
    }

    private func validate(serviceURL: URL, provider: SpeechSynthesisProvider) throws {
        let scheme = serviceURL.scheme?.lowercased()
        let host = serviceURL.host?.lowercased() ?? ""
        switch provider {
        case .openAI:
            guard scheme == "https", host == "api.openai.com" else {
                throw SpeechServiceError.invalidServiceURL
            }
        case .openAICompatibleLocal:
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            let isIPv4Loopback = parts.count == 4 && parts.first == "127" && parts.allSatisfy { part in
                guard let value = Int(part) else { return false }
                return (0 ... 255).contains(value)
            }
            guard ["http", "https"].contains(scheme), host == "localhost" || host == "::1" || isIPv4Loopback
            else {
                throw SpeechServiceError.invalidServiceURL
            }
        default:
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private struct SynthesisRequestBody: Encodable {
        let model: String
        let input: String
        let voice: String
        let instructions: String?
        let responseFormat: String
        let speed: Double

        enum CodingKeys: String, CodingKey {
            case model
            case input
            case voice
            case instructions
            case responseFormat = "response_format"
            case speed
        }
    }
}

@MainActor
public final class OpenAISpeechSynthesizer: SpeechSynthesizing {
    private let client: OpenAISpeechEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: OpenAISpeechEngineClient = OpenAISpeechEngineClient()) {
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

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
