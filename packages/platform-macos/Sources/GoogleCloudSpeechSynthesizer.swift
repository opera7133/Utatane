import Foundation

public struct GoogleCloudSpeechEngineClient: Sendable {
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
            SpeechCredentialStore.load(provider: .googleCloudTTS, scope: $0)
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
        let serviceURL = try serviceURL()
        let apiKey = try apiKey(scope: scope)
        let url = serviceURL.appending(path: "voices", directoryHint: .notDirectory)
        let (data, response) = try await transport(authenticatedRequest(url: url, apiKey: apiKey))
        try validate(response)
        let result: VoicesResponse
        do {
            result = try JSONDecoder().decode(VoicesResponse.self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        return result.voices.flatMap { voice in
            voice.languageCodes.map { language in
                SpeechSynthesisVoice(
                    identifier: voice.name,
                    languageIdentifier: language,
                    name: voice.name,
                    language: language
                )
            }
        }.sorted {
            if $0.language == $1.language {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            } else {
                $0.language.localizedStandardCompare($1.language) == .orderedAscending
            }
        }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Data() }
        guard let configuredURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(configuredURL)
        guard let voiceName = request.configuration.voiceIdentifier?.nilIfBlank else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let languageCode = request.configuration.voiceLanguageIdentifier?.nilIfBlank
            ?? inferredLocale(from: voiceName)
        let apiKey = try apiKey(scope: request.scope)
        let url = configuredURL.appending(path: "text:synthesize", directoryHint: .notDirectory)
        var urlRequest = authenticatedRequest(url: url, apiKey: apiKey)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = SynthesisRequestBody(
            input: .init(text: text),
            voice: .init(languageCode: languageCode, name: voiceName),
            audioConfig: .init(
                audioEncoding: "MP3",
                speakingRate: min(2, max(0.25, Double(request.configuration.rate) / 0.5)),
                pitch: min(20, max(-20, (Double(request.configuration.pitchMultiplier) - 1) * 12))
            )
        )
        do {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }

        let (data, response) = try await transport(urlRequest)
        try validate(response)
        let result: SynthesisResponse
        do {
            result = try JSONDecoder().decode(SynthesisResponse.self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        guard let audio = Data(base64Encoded: result.audioContent), !audio.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return audio
    }

    private func serviceURL() throws -> URL {
        guard let url = URL(string: "https://texttospeech.googleapis.com/v1") else {
            throw SpeechServiceError.invalidServiceURL
        }
        return url
    }

    private func authenticatedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
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
              serviceURL.host?.lowercased() == "texttospeech.googleapis.com"
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private func inferredLocale(from voiceName: String) -> String {
        let parts = voiceName.split(separator: "-")
        guard parts.count >= 2 else { return "ja-JP" }
        return "\(parts[0])-\(parts[1])"
    }

    private struct VoicesResponse: Decodable {
        let voices: [Voice]
    }

    private struct Voice: Decodable {
        let languageCodes: [String]
        let name: String
    }

    private struct SynthesisRequestBody: Encodable {
        let input: SynthesisInput
        let voice: VoiceSelection
        let audioConfig: AudioConfig
    }

    private struct SynthesisInput: Encodable {
        let text: String
    }

    private struct VoiceSelection: Encodable {
        let languageCode: String
        let name: String
    }

    private struct AudioConfig: Encodable {
        let audioEncoding: String
        let speakingRate: Double
        let pitch: Double
    }

    private struct SynthesisResponse: Decodable {
        let audioContent: String
    }
}

@MainActor
public final class GoogleCloudSpeechSynthesizer: SpeechSynthesizing {
    private let client: GoogleCloudSpeechEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: GoogleCloudSpeechEngineClient = GoogleCloudSpeechEngineClient()) {
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
