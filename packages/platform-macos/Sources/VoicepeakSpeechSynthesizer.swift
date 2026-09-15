import Foundation

public final class VoicepeakEngineClient: @unchecked Sendable {
    typealias CommandRunner = @Sendable (URL, [String]) async throws -> ProcessOutput

    private let lock = NSLock()
    private var runningProcess: Process?
    private let commandRunner: CommandRunner?

    public init() {
        commandRunner = nil
    }

    init(commandRunner: @escaping CommandRunner) {
        self.commandRunner = commandRunner
    }

    public func voices(executableURL: URL) async throws -> [SpeechSynthesisVoice] {
        let output = try await run(executableURL: executableURL, arguments: ["--list-narrator"])
        return String(decoding: output.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { SpeechSynthesisVoice(identifier: $0, name: $0, language: "VOICEPEAK") }
    }

    public func synthesize(_ request: SpeechSynthesisRequest) async throws -> Data {
        guard let executableURL = request.configuration.serviceURL, executableURL.isFileURL else {
            throw SpeechServiceError.invalidServiceURL
        }
        guard let narrator = request.configuration.voiceIdentifier, !narrator.isEmpty else {
            throw SpeechServiceError.invalidVoiceIdentifier
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "utatane-voicepeak-\(UUID().uuidString).wav", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let speed = min(200, max(50, Int((request.configuration.rate / 0.5 * 100).rounded())))
        let pitch = min(300, max(-300, Int(((request.configuration.pitchMultiplier - 1) * 300).rounded())))
        _ = try await run(
            executableURL: executableURL,
            arguments: [
                "--say", request.text,
                "--narrator", narrator,
                "--out", outputURL.path,
                "--speed", String(speed),
                "--pitch", String(pitch)
            ]
        )
        guard let audio = try? Data(contentsOf: outputURL), !audio.isEmpty else {
            throw SpeechServiceError.invalidServiceResponse
        }
        return audio
    }

    public func stop() {
        let process = lock.withLock { runningProcess }
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    private func run(executableURL: URL, arguments: [String]) async throws -> ProcessOutput {
        if let commandRunner {
            return try await commandRunner(executableURL, arguments)
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeechServiceError.invalidServiceURL
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = standardOutput
                process.standardError = standardError
                process.terminationHandler = { [weak self] process in
                    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
                    let error = standardError.fileHandleForReading.readDataToEndOfFile()
                    self?.lock.withLock { self?.runningProcess = nil }
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: ProcessOutput(standardOutput: output))
                    } else {
                        let message = String(decoding: error, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: SpeechServiceError.externalProcessFailed(
                            process.terminationStatus,
                            message
                        ))
                    }
                }
                do {
                    self.lock.withLock { self.runningProcess = process }
                    try process.run()
                } catch {
                    self.lock.withLock { self.runningProcess = nil }
                    continuation.resume(throwing: SpeechServiceError.invalidServiceURL)
                }
            }
        } onCancel: {
            stop()
        }
    }

    struct ProcessOutput: Sendable {
        let standardOutput: Data
    }
}

@MainActor
public final class VoicepeakSpeechSynthesizer: SpeechSynthesizing {
    private let client: VoicepeakEngineClient
    private let audioPlayer = SpeechAudioDataPlayer()
    private var requestTask: Task<Data, Error>?

    public init(client: VoicepeakEngineClient = VoicepeakEngineClient()) {
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
        client.stop()
        audioPlayer.stop()
    }
}
