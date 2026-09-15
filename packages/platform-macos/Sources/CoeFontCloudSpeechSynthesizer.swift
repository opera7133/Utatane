import CryptoKit
import Foundation

public struct CoeFontCloudEngineClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias CredentialProvider = @Sendable (Int) -> SpeechCredentialStore.Credential
    typealias DateProvider = @Sendable () -> Date

    private let transport: Transport
    private let credentialProvider: CredentialProvider
    private let dateProvider: DateProvider

    public init(session: URLSession = .shared) {
        transport = { request in
            let delegate = CoeFontRedirectSanitizingDelegate()
            let (data, response) = try await session.data(for: request, delegate: delegate)
            guard let response = response as? HTTPURLResponse else {
                throw SpeechServiceError.invalidServiceResponse
            }
            return (data, response)
        }
        credentialProvider = {
            SpeechCredentialStore.load(provider: .coeFontCloud, scope: $0)
        }
        dateProvider = Date.init
    }

    init(
        transport: @escaping Transport,
        credentialProvider: @escaping CredentialProvider,
        dateProvider: @escaping DateProvider = Date.init
    ) {
        self.transport = transport
        self.credentialProvider = credentialProvider
        self.dateProvider = dateProvider
    }

    public func voices(scope: Int) async throws -> [SpeechSynthesisVoice] {
        let serviceURL = try serviceURL()
        let credential = try credential(scope: scope)
        let url = serviceURL.appending(path: "coefonts/pro", directoryHint: .notDirectory)
        let request = signedRequest(url: url, method: "GET", body: nil, credential: credential)
        let (data, response) = try await transport(request)
        try validate(response)
        let voices: [Voice]
        do {
            voices = try JSONDecoder().decode([Voice].self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        return voices.map {
            SpeechSynthesisVoice(identifier: $0.coefont, name: $0.name, language: "")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Data() }
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(serviceURL)
        guard let voiceID = request.configuration.voiceIdentifier?.nilIfBlank else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let credential = try credential(scope: request.scope)
        let body: Data
        do {
            body = try JSONEncoder().encode(SynthesisRequestBody(
                coefont: voiceID,
                text: text,
                speed: min(10, max(0.1, Double(request.configuration.rate) / 0.5)),
                pitch: min(3000, max(-3000, (Double(request.configuration.pitchMultiplier) - 1) * 1200)),
                format: "mp3"
            ))
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        let url = serviceURL.appending(path: "text2speech", directoryHint: .notDirectory)
        let urlRequest = signedRequest(url: url, method: "POST", body: body, credential: credential)
        let (data, response) = try await transport(urlRequest)
        try validate(response)
        guard !data.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return data
    }

    private func serviceURL() throws -> URL {
        guard let url = URL(string: "https://api.coefont.cloud/v2") else {
            throw SpeechServiceError.invalidServiceURL
        }
        return url
    }

    private func credential(scope: Int) throws -> SpeechCredentialStore.Credential {
        let credential = credentialProvider(scope)
        guard credential.isComplete else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }
        return credential
    }

    private func signedRequest(
        url: URL,
        method: String,
        body: Data?,
        credential: SpeechCredentialStore.Credential
    ) -> URLRequest {
        let timestamp = String(Int(dateProvider().timeIntervalSince1970))
        var signedContent = Data(timestamp.utf8)
        if let body {
            signedContent.append(body)
        }
        let signature = HMAC<SHA256>.authenticationCode(
            for: signedContent,
            using: SymmetricKey(data: Data(credential.password.utf8))
        ).map { String(format: "%02x", $0) }.joined()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(credential.username, forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-Coefont-Date")
        request.setValue(signature, forHTTPHeaderField: "X-Coefont-Content")
        return request
    }

    private func validate(_ serviceURL: URL) throws {
        guard serviceURL.scheme?.lowercased() == "https",
              serviceURL.host?.lowercased() == "api.coefont.cloud",
              serviceURL.path == "/v2"
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private struct Voice: Decodable {
        let coefont: String
        let name: String
    }

    private struct SynthesisRequestBody: Encodable {
        let coefont: String
        let text: String
        let speed: Double
        let pitch: Double
        let format: String
    }
}

final class CoeFontRedirectSanitizingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "X-Coefont-Date")
        request.setValue(nil, forHTTPHeaderField: "X-Coefont-Content")
        completionHandler(request)
    }
}

@MainActor
public final class CoeFontCloudSpeechSynthesizer: SpeechSynthesizing {
    private let client: CoeFontCloudEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: CoeFontCloudEngineClient = CoeFontCloudEngineClient()) {
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
