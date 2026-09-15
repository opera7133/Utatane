import Foundation

public struct VoiSonaTalkEngineClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias Sleeper = @Sendable () async throws -> Void
    typealias CredentialProvider = @Sendable (Int) -> SpeechCredentialStore.Credential

    private let transport: Transport
    private let sleeper: Sleeper
    private let credentialProvider: CredentialProvider

    public init(session: URLSession = .shared) {
        transport = { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw SpeechServiceError.invalidServiceResponse
            }
            return (data, response)
        }
        sleeper = { try await Task.sleep(for: .milliseconds(100)) }
        credentialProvider = { SpeechCredentialStore.load(scope: $0) }
    }

    init(
        transport: @escaping Transport,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: .milliseconds(100)) },
        credentialProvider: @escaping CredentialProvider
    ) {
        self.transport = transport
        self.sleeper = sleeper
        self.credentialProvider = credentialProvider
    }

    public func voices(
        serviceURL: URL,
        credential: SpeechCredentialStore.Credential
    ) async throws -> [SpeechSynthesisVoice] {
        guard credential.isComplete else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }
        let url = try endpoint("voices", at: serviceURL)
        let (data, response) = try await transport(authenticatedRequest(url: url, credential: credential))
        try validate(response)
        let responseBody: VoicesResponse
        do {
            responseBody = try JSONDecoder().decode(VoicesResponse.self, from: data)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        return responseBody.items.flatMap { voice in
            voice.languages.map { language in
                SpeechSynthesisVoice(
                    identifier: voice.voiceName,
                    groupIdentifier: voice.voiceVersion,
                    languageIdentifier: language,
                    name: voice.displayNames.first(where: { $0.language == language })?.name
                        ?? voice.displayNames.first?.name
                        ?? voice.voiceName,
                    language: language
                )
            }
        }
        .sorted {
            if $0.name == $1.name {
                return $0.language.localizedStandardCompare($1.language) == .orderedAscending
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        guard let serviceURL = request.configuration.serviceURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        guard let voiceName = request.configuration.voiceIdentifier,
              !voiceName.isEmpty,
              let voiceVersion = request.configuration.voiceGroupIdentifier,
              !voiceVersion.isEmpty,
              let language = request.configuration.voiceLanguageIdentifier,
              !language.isEmpty
        else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let credential = credentialProvider(request.scope)
        guard credential.isComplete else {
            throw SpeechServiceError.serviceCredentialsUnavailable
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "utatane-voisona-\(UUID().uuidString).wav", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let createURL = try endpoint("speech-syntheses", at: serviceURL)
        var createRequest = authenticatedRequest(url: createURL, credential: credential)
        createRequest.httpMethod = "POST"
        createRequest.timeoutInterval = 30
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = SynthesisRequestBody(
            text: request.text,
            language: language,
            voiceName: voiceName,
            voiceVersion: voiceVersion,
            outputFilePath: outputURL.path,
            globalParameters: GlobalParameters(
                pitch: min(600, max(-600, (Double(request.configuration.pitchMultiplier) - 1) * 600)),
                speed: min(5, max(0.2, Double(request.configuration.rate) / 0.5))
            )
        )
        do {
            createRequest.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }

        let (createData, createResponse) = try await transport(createRequest)
        try validate(createResponse)
        let job: JobResponse
        do {
            job = try JSONDecoder().decode(JobResponse.self, from: createData)
        } catch {
            throw SpeechServiceError.invalidServiceResponse
        }
        guard !job.uuid.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }

        do {
            try await waitForCompletion(jobID: job.uuid, serviceURL: serviceURL, credential: credential)
            guard let audio = try? Data(contentsOf: outputURL), !audio.isEmpty else {
                throw SpeechServiceError.invalidServiceResponse
            }
            await deleteJob(job.uuid, serviceURL: serviceURL, credential: credential)
            return audio
        } catch {
            await deleteJob(job.uuid, serviceURL: serviceURL, credential: credential)
            throw error
        }
    }

    private func waitForCompletion(
        jobID: String,
        serviceURL: URL,
        credential: SpeechCredentialStore.Credential
    ) async throws {
        let statusURL = try endpoint("speech-syntheses/\(jobID)", at: serviceURL)
        for _ in 0 ..< 300 {
            try Task.checkCancellation()
            var request = authenticatedRequest(url: statusURL, credential: credential)
            request.timeoutInterval = 10
            let (data, response) = try await transport(request)
            try validate(response)
            let status: JobStatus
            do {
                status = try JSONDecoder().decode(JobStatus.self, from: data)
            } catch {
                throw SpeechServiceError.invalidServiceResponse
            }
            switch status.state {
            case "succeeded":
                return
            case "failed", "cancelled", "canceled":
                throw SpeechServiceError.invalidServiceResponse
            default:
                try await sleeper()
            }
        }
        throw SpeechServiceError.invalidServiceResponse
    }

    private func deleteJob(
        _ jobID: String,
        serviceURL: URL,
        credential: SpeechCredentialStore.Credential
    ) async {
        guard let url = try? endpoint("speech-syntheses/\(jobID)", at: serviceURL) else { return }
        var request = authenticatedRequest(url: url, credential: credential)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        _ = try? await transport(request)
    }

    private func endpoint(_ path: String, at serviceURL: URL) throws -> URL {
        let host = serviceURL.host?.lowercased() ?? ""
        let addressParts = host.split(separator: ".", omittingEmptySubsequences: false)
        let isIPv4Loopback = addressParts.count == 4 && addressParts.first == "127" &&
            addressParts.allSatisfy { part in
                guard let value = Int(part) else { return false }
                return (0 ... 255).contains(value)
            }
        let isLoopback = host == "localhost" || host == "::1" || isIPv4Loopback
        guard ["http", "https"].contains(serviceURL.scheme?.lowercased()), isLoopback else {
            throw SpeechServiceError.invalidServiceURL
        }
        return path.split(separator: "/").reduce(serviceURL) { url, component in
            url.appending(path: String(component), directoryHint: .notDirectory)
        }
    }

    private func authenticatedRequest(
        url: URL,
        credential: SpeechCredentialStore.Credential
    ) -> URLRequest {
        var request = URLRequest(url: url)
        let token = Data("\(credential.username):\(credential.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200 ..< 300).contains(response.statusCode) else {
            throw SpeechServiceError.serviceResponse(response.statusCode)
        }
    }

    private struct VoicesResponse: Decodable {
        let items: [Voice]
    }

    private struct Voice: Decodable {
        let displayNames: [DisplayName]
        let languages: [String]
        let voiceName: String
        let voiceVersion: String

        enum CodingKeys: String, CodingKey {
            case displayNames = "display_names"
            case languages
            case voiceName = "voice_name"
            case voiceVersion = "voice_version"
        }
    }

    private struct DisplayName: Decodable {
        let language: String
        let name: String
    }

    private struct JobResponse: Decodable {
        let uuid: String
    }

    private struct JobStatus: Decodable {
        let state: String
    }

    private struct SynthesisRequestBody: Encodable {
        let text: String
        let language: String
        let voiceName: String
        let voiceVersion: String
        let forceEnqueue = true
        let destination = "file"
        let outputFilePath: String
        let canOverwriteFile = true
        let globalParameters: GlobalParameters

        enum CodingKeys: String, CodingKey {
            case text
            case language
            case voiceName = "voice_name"
            case voiceVersion = "voice_version"
            case forceEnqueue = "force_enqueue"
            case destination
            case outputFilePath = "output_file_path"
            case canOverwriteFile = "can_overwrite_file"
            case globalParameters = "global_parameters"
        }
    }

    private struct GlobalParameters: Encodable {
        let pitch: Double
        let speed: Double
    }
}

@MainActor
public final class VoiSonaTalkSpeechSynthesizer: SpeechSynthesizing {
    private let client: VoiSonaTalkEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: VoiSonaTalkEngineClient = VoiSonaTalkEngineClient()) {
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
        try await audioPlayer.play(audio, volume: request.configuration.volume)
    }

    public func stop() {
        requestTask?.cancel()
        requestTask = nil
        audioPlayer.stop()
    }
}
