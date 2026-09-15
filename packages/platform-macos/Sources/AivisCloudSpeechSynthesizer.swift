import Foundation

public struct AivisCloudEngineClient: Sendable {
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
            SpeechCredentialStore.load(provider: .aivisCloud, scope: $0)
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
        try validate(serviceURL)
        guard let modelUUID = request.configuration.voiceIdentifier, !modelUUID.isEmpty else {
            throw SpeechServiceError.invalidModelIdentifier
        }
        let styleID: Int?
        if let value = request.configuration.styleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty
        {
            guard let parsed = Int(value) else {
                throw SpeechServiceError.invalidVoiceIdentifier
            }
            styleID = parsed
        } else {
            styleID = nil
        }
        let apiKey = credentialProvider(request.scope).password
        guard !apiKey.isEmpty else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }

        var url = serviceURL
        for component in ["tts", "synthesize"] {
            url.append(path: component, directoryHint: .notDirectory)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = SynthesisRequestBody(
            modelUUID: modelUUID,
            text: text,
            speakerUUID: request.configuration.voiceGroupIdentifier?.nilIfBlank,
            styleID: styleID,
            useSSML: false,
            speakingRate: min(2, max(0.5, Double(request.configuration.rate) / 0.5)),
            pitch: min(1, max(-1, Double(request.configuration.pitchMultiplier) - 1)),
            outputFormat: "mp3",
            leadingSilenceSeconds: 0
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

    private func validate(_ serviceURL: URL) throws {
        guard serviceURL.scheme?.lowercased() == "https",
              serviceURL.host?.lowercased() == "api.aivis-project.com"
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private struct SynthesisRequestBody: Encodable {
        let modelUUID: String
        let text: String
        let speakerUUID: String?
        let styleID: Int?
        let useSSML: Bool
        let speakingRate: Double
        let pitch: Double
        let outputFormat: String
        let leadingSilenceSeconds: Double

        enum CodingKeys: String, CodingKey {
            case modelUUID = "model_uuid"
            case text
            case speakerUUID = "speaker_uuid"
            case styleID = "style_id"
            case useSSML = "use_ssml"
            case speakingRate = "speaking_rate"
            case pitch
            case outputFormat = "output_format"
            case leadingSilenceSeconds = "leading_silence_seconds"
        }
    }
}

@MainActor
public final class AivisCloudSpeechSynthesizer: SpeechSynthesizing {
    private let client: AivisCloudEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: AivisCloudEngineClient = AivisCloudEngineClient()) {
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
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
