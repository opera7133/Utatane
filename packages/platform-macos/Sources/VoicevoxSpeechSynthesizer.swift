import AVFoundation
import Foundation

public struct VoicevoxEngineClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let transport: Transport

    public init(session: URLSession = .shared) {
        transport = { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw SpeechServiceError.invalidServiceResponse
            }
            return (data, response)
        }
    }

    init(transport: @escaping Transport) {
        self.transport = transport
    }

    public func voices(serviceURL: URL) async throws -> [SpeechSynthesisVoice] {
        let url = try endpoint("speakers", at: serviceURL)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await transport(request)
        try validate(response)
        let speakers: [Speaker]
        do {
            speakers = try JSONDecoder().decode([Speaker].self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        return speakers.flatMap { speaker in
            speaker.styles.map { style in
                SpeechSynthesisVoice(
                    identifier: String(style.id),
                    name: "\(speaker.name) — \(style.name)",
                    language: "VOICEVOX API"
                )
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        guard let identifier = request.configuration.voiceIdentifier,
              let speaker = Int(identifier)
        else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }

        let queryURL = try endpoint(
            "audio_query",
            at: serviceURL,
            queryItems: [
                URLQueryItem(name: "text", value: request.text),
                URLQueryItem(name: "speaker", value: String(speaker))
            ]
        )
        var queryRequest = URLRequest(url: queryURL)
        queryRequest.httpMethod = "POST"
        queryRequest.httpBody = Data()
        queryRequest.timeoutInterval = 30
        let (queryData, queryResponse) = try await transport(queryRequest)
        try validate(queryResponse)

        let adjustedQuery = try adjustedAudioQuery(queryData, configuration: request.configuration)
        let synthesisURL = try endpoint(
            "synthesis",
            at: serviceURL,
            queryItems: [URLQueryItem(name: "speaker", value: String(speaker))]
        )
        var synthesisRequest = URLRequest(url: synthesisURL)
        synthesisRequest.httpMethod = "POST"
        synthesisRequest.httpBody = adjustedQuery
        synthesisRequest.timeoutInterval = 120
        synthesisRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        synthesisRequest.setValue("audio/wav", forHTTPHeaderField: "Accept")
        let (audio, synthesisResponse) = try await transport(synthesisRequest)
        try validate(synthesisResponse)
        guard !audio.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return audio
    }

    private func adjustedAudioQuery(
        _ data: Data,
        configuration: SpeechSynthesisConfiguration
    ) throws -> Data {
        guard var query = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpeechServiceError.invalidServiceResponse
        }
        query["speedScale"] = min(2, max(0.5, Double(configuration.rate) / 0.5))
        query["volumeScale"] = min(2, max(0, Double(configuration.volume)))
        query["pitchScale"] = min(0.15, max(-0.15, (Double(configuration.pitchMultiplier) - 1) * 0.15))
        do {
            return try JSONSerialization.data(withJSONObject: query)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
    }

    private func endpoint(
        _ path: String,
        at serviceURL: URL,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard ["http", "https"].contains(serviceURL.scheme?.lowercased()),
              serviceURL.host != nil
        else {
            throw SpeechServiceError.invalidServiceURL
        }
        let endpoint = serviceURL.appending(path: path, directoryHint: .notDirectory)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SpeechServiceError.invalidServiceURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw SpeechServiceError.invalidServiceURL
        }
        return url
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private struct Speaker: Decodable {
        let name: String
        let styles: [Style]
    }

    private struct Style: Decodable {
        let name: String
        let id: Int
    }
}

@MainActor
public final class VoicevoxSpeechSynthesizer: SpeechSynthesizing {
    private let client: VoicevoxEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: VoicevoxEngineClient = VoicevoxEngineClient()) {
        self.client = client
    }

    public func speak(_ request: SpeechSynthesisRequest) async throws {
        stop()
        try Task.checkCancellation()
        let task = Task { try await client.synthesize(request) }
        requestTask = task
        defer { requestTask = nil }
        let audio = try await task.value
        try Task.checkCancellation()
        try await audioPlayer.play(audio)
    }

    public func stop() {
        requestTask?.cancel()
        requestTask = nil
        audioPlayer.stop()
    }
}

@MainActor
final class SpeechAudioDataPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    func play(_ data: Data, volume: Float = 1) async throws {
        stop()
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw SpeechServiceError.audioPlaybackFailed
        }
        player.delegate = self
        player.volume = min(max(volume, 0), 1)
        self.player = player
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard player.prepareToPlay(), player.play() else {
                    self.player = nil
                    finish(.failure(SpeechServiceError.audioPlaybackFailed))
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        finish(.failure(SpeechServiceError.synthesisCancelled))
    }

    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.finish(flag ? .success(()) : .failure(SpeechServiceError.audioPlaybackFailed))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
