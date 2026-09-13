import Foundation

public struct CoeiroinkEngineClient: Sendable {
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
        let url = try endpoint("v1/speakers", at: serviceURL)
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
                    identifier: String(style.styleId),
                    groupIdentifier: speaker.speakerUuid,
                    name: "\(speaker.speakerName) — \(style.styleName)",
                    language: "COEIROINK v2"
                )
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        guard let speakerUuid = request.configuration.voiceGroupIdentifier,
              !speakerUuid.isEmpty,
              let identifier = request.configuration.voiceIdentifier,
              let styleId = Int(identifier)
        else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }

        let url = try endpoint("v1/synthesis", at: serviceURL)
        var synthesisRequest = URLRequest(url: url)
        synthesisRequest.httpMethod = "POST"
        synthesisRequest.timeoutInterval = 120
        synthesisRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        synthesisRequest.setValue("audio/wav", forHTTPHeaderField: "Accept")
        let body = SynthesisRequestBody(
            speakerUuid: speakerUuid,
            styleId: styleId,
            text: request.text,
            speedScale: min(2, max(0.5, Double(request.configuration.rate) / 0.5)),
            volumeScale: min(2, max(0, Double(request.configuration.volume))),
            pitchScale: min(0.15, max(-0.15, (Double(request.configuration.pitchMultiplier) - 1) * 0.15))
        )
        do {
            synthesisRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }

        let (audio, response) = try await transport(synthesisRequest)
        try validate(response)
        guard !audio.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return audio
    }

    private func endpoint(_ path: String, at serviceURL: URL) throws -> URL {
        guard ["http", "https"].contains(serviceURL.scheme?.lowercased()),
              serviceURL.host != nil
        else {
            throw SpeechServiceError.invalidServiceURL
        }
        return serviceURL.appending(path: path, directoryHint: .notDirectory)
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private struct Speaker: Decodable {
        let speakerName: String
        let speakerUuid: String
        let styles: [Style]
    }

    private struct Style: Decodable {
        let styleName: String
        let styleId: Int
    }

    private struct SynthesisRequestBody: Encodable {
        let speakerUuid: String
        let styleId: Int
        let text: String
        let speedScale: Double
        let volumeScale: Double
        let pitchScale: Double
        let intonationScale = 1.0
        let prePhonemeLength = 0.0
        let postPhonemeLength = 0.0
        let outputSamplingRate = 44100
        let sampledIntervalValue = 0
        let adjustedF0: [Double] = []
        let processingAlgorithm = "coeiroink"
        let prosodyDetail: [String] = []
    }
}

@MainActor
public final class CoeiroinkSpeechSynthesizer: SpeechSynthesizing {
    private let client: CoeiroinkEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: CoeiroinkEngineClient = CoeiroinkEngineClient()) {
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
