import Foundation

public struct AITalkWebAPIEngineClient: Sendable {
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
            SpeechCredentialStore.load(provider: .aiTalkWebAPI, scope: $0)
        }
    }

    init(
        transport: @escaping Transport,
        credentialProvider: @escaping CredentialProvider
    ) {
        self.transport = transport
        self.credentialProvider = credentialProvider
    }

    public static let standardVoices: [SpeechSynthesisVoice] = [
        .init(identifier: "nozomi_emo", name: "のぞみ（感情）", language: "ja-JP"),
        .init(identifier: "nozomi_dnn", name: "のぞみ（DNN）", language: "ja-JP"),
        .init(identifier: "nozomi", name: "のぞみ", language: "ja-JP"),
        .init(identifier: "kaho_emo", name: "かほ（感情）", language: "ja-JP"),
        .init(identifier: "kaho_dnn", name: "かほ（DNN）", language: "ja-JP"),
        .init(identifier: "kaho", name: "かほ", language: "ja-JP"),
        .init(identifier: "akari", name: "あかり", language: "ja-JP"),
        .init(identifier: "nanako", name: "ななこ", language: "ja-JP"),
        .init(identifier: "shiori_emo", name: "しおり（感情）", language: "ja-JP"),
        .init(identifier: "shiori", name: "しおり", language: "ja-JP"),
        .init(identifier: "kanon", name: "かのん", language: "ja-JP"),
        .init(identifier: "yumiko", name: "ゆみこ", language: "ja-JP"),
        .init(identifier: "tsubasa", name: "つばさ", language: "ja-JP"),
        .init(identifier: "emiri_emo", name: "えみり（感情）", language: "ja-JP"),
        .init(identifier: "kenta_emo", name: "けんた（感情）", language: "ja-JP"),
        .init(identifier: "kenta_dnn", name: "けんた（DNN）", language: "ja-JP"),
        .init(identifier: "kenta", name: "けんた", language: "ja-JP"),
        .init(identifier: "taichi_emo", name: "たいち（感情）", language: "ja-JP"),
        .init(identifier: "taichi_dnn", name: "たいち（DNN）", language: "ja-JP"),
        .init(identifier: "taichi", name: "たいち", language: "ja-JP"),
        .init(identifier: "seiji_emo", name: "せいじ（感情）", language: "ja-JP"),
        .init(identifier: "seiji_dnn", name: "せいじ（DNN）", language: "ja-JP"),
        .init(identifier: "seiji", name: "せいじ", language: "ja-JP"),
        .init(identifier: "osamu", name: "おさむ", language: "ja-JP"),
        .init(identifier: "hideto_emo", name: "ひでと（感情）", language: "ja-JP"),
        .init(identifier: "anzu", name: "あんず", language: "ja-JP"),
        .init(identifier: "chihiro", name: "ちひろ", language: "ja-JP"),
        .init(identifier: "koutarou", name: "こうたろう", language: "ja-JP"),
        .init(identifier: "yuuto", name: "ゆうと", language: "ja-JP"),
        .init(identifier: "miyabi_west", name: "みやび（関西弁）", language: "ja-JP"),
        .init(identifier: "yamato_west", name: "やまと（関西弁）", language: "ja-JP"),
        .init(identifier: "Danielle", name: "Danielle", language: "en-US"),
        .init(identifier: "Gregory", name: "Gregory", language: "en-US"),
        .init(identifier: "Ivy", name: "Ivy", language: "en-US"),
        .init(identifier: "Joanna", name: "Joanna", language: "en-US"),
        .init(identifier: "Kendra", name: "Kendra", language: "en-US"),
        .init(identifier: "Kimberly", name: "Kimberly", language: "en-US"),
        .init(identifier: "Salli", name: "Salli", language: "en-US"),
        .init(identifier: "Joey", name: "Joey", language: "en-US"),
        .init(identifier: "Justin", name: "Justin", language: "en-US"),
        .init(identifier: "Kevin", name: "Kevin", language: "en-US"),
        .init(identifier: "Matthew", name: "Matthew", language: "en-US"),
        .init(identifier: "Ruth", name: "Ruth", language: "en-US"),
        .init(identifier: "Stephen", name: "Stephen", language: "en-US"),
        .init(identifier: "Zhiyu", name: "Zhiyu", language: "zh-CN"),
        .init(identifier: "Hiujin", name: "Hiujin", language: "zh-HK"),
        .init(identifier: "Seoyeon", name: "Seoyeon", language: "ko-KR")
    ]

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Data() }
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        try validate(serviceURL)
        guard let speakerName = request.configuration.voiceIdentifier?.nilIfBlank else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let credential = credentialProvider(request.scope)
        guard credential.isComplete else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }

        let url = serviceURL.appending(path: "ttsget.php", directoryHint: .notDirectory)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        var form = URLComponents()
        form.queryItems = [
            .init(name: "username", value: credential.username),
            .init(name: "password", value: credential.password),
            .init(name: "speaker_name", value: speakerName),
            .init(name: "input_type", value: "text"),
            .init(name: "text", value: text),
            .init(name: "ext", value: "mp3"),
            .init(name: "fs", value: "auto"),
            .init(name: "speed", value: decimal(min(4, max(0.5, Double(request.configuration.rate) / 0.5)))),
            .init(name: "pitch", value: decimal(min(2, max(0.5, Double(request.configuration.pitchMultiplier))))),
            .init(name: "tpause", value: "0")
        ]
        let percentEncodedForm = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let body = percentEncodedForm?.data(using: .utf8) else {
            throw SpeechServiceError.invalidServiceResponse
        }
        urlRequest.httpBody = body

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
              serviceURL.host?.lowercased() == "webapi.aitalk.jp",
              serviceURL.path == "/webapi/v5"
        else {
            throw SpeechServiceError.invalidServiceURL
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

@MainActor
public final class AITalkWebAPISpeechSynthesizer: SpeechSynthesizing {
    private let client: AITalkWebAPIEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: AITalkWebAPIEngineClient = AITalkWebAPIEngineClient()) {
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
