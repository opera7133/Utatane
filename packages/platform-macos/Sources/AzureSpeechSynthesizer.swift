import Foundation

public struct AzureSpeechEngineClient: Sendable {
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
            SpeechCredentialStore.load(provider: .azureSpeech, scope: $0)
        }
    }

    init(
        transport: @escaping Transport,
        credentialProvider: @escaping CredentialProvider
    ) {
        self.transport = transport
        self.credentialProvider = credentialProvider
    }

    public func voices(serviceURL: URL, scope: Int) async throws -> [SpeechSynthesisVoice] {
        try validate(serviceURL)
        let apiKey = try apiKey(scope: scope)
        var url = serviceURL
        for component in ["cognitiveservices", "voices", "list"] {
            url.append(path: component, directoryHint: .notDirectory)
        }
        let (data, response) = try await transport(authenticatedRequest(url: url, apiKey: apiKey))
        try validate(response)
        let voices: [Voice]
        do {
            voices = try JSONDecoder().decode([Voice].self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        return voices.map {
            SpeechSynthesisVoice(
                identifier: $0.shortName,
                languageIdentifier: $0.locale,
                name: "\($0.localName) — \($0.shortName)",
                language: $0.locale
            )
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
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(serviceURL)
        guard let voice = request.configuration.voiceIdentifier?.nilIfBlank else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let language = request.configuration.voiceLanguageIdentifier?.nilIfBlank ?? inferredLocale(from: voice)
        let apiKey = try apiKey(scope: request.scope)

        var url = serviceURL
        for component in ["cognitiveservices", "v1"] {
            url.append(path: component, directoryHint: .notDirectory)
        }
        var urlRequest = authenticatedRequest(url: url, apiKey: apiKey)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        urlRequest.setValue("Utatane", forHTTPHeaderField: "User-Agent")
        let rate = min(200, max(50, Double(request.configuration.rate) / 0.5 * 100))
        let pitch = min(100, max(-50, (Double(request.configuration.pitchMultiplier) - 1) * 100))
        let rateValue = String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), rate)
        let pitchValue = String(format: "%+.0f%%", locale: Locale(identifier: "en_US_POSIX"), pitch)
        let ssml = "<speak version='1.0' xml:lang='\(language.xmlEscaped)'>" +
            "<voice name='\(voice.xmlEscaped)'><prosody rate='\(rateValue)' pitch='\(pitchValue)'>" +
            "\(text.xmlEscaped)</prosody></voice></speak>"
        urlRequest.httpBody = Data(ssml.utf8)

        let (data, response) = try await transport(urlRequest)
        try validate(response)
        guard !data.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return data
    }

    private func authenticatedRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
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
        let hostParts = serviceURL.host?.lowercased().split(separator: ".") ?? []
        guard serviceURL.scheme?.lowercased() == "https",
              hostParts.count == 5,
              Array(hostParts.dropFirst()) == ["tts", "speech", "microsoft", "com"],
              hostParts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private func inferredLocale(from voice: String) -> String {
        let parts = voice.split(separator: "-")
        guard parts.count >= 2 else { return "ja-JP" }
        return "\(parts[0])-\(parts[1])"
    }

    private struct Voice: Decodable {
        let shortName: String
        let localName: String
        let locale: String

        enum CodingKeys: String, CodingKey {
            case shortName = "ShortName"
            case localName = "LocalName"
            case locale = "Locale"
        }
    }
}

@MainActor
public final class AzureSpeechSynthesizer: SpeechSynthesizing {
    private let client: AzureSpeechEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: AzureSpeechEngineClient = AzureSpeechEngineClient()) {
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

    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
