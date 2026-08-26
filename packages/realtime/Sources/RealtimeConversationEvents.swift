import Foundation

public enum RealtimeTranscriptPhase: Sendable, Equatable {
    case partial
    case final
}

public enum RealtimeTranscriptRole: Sendable, Equatable {
    case user
    case assistant
}

public struct RealtimeTranscriptUpdate: Sendable, Equatable {
    public let text: String
    public let phase: RealtimeTranscriptPhase
    public let role: RealtimeTranscriptRole

    public init(text: String, phase: RealtimeTranscriptPhase, role: RealtimeTranscriptRole = .assistant) {
        self.text = text
        self.phase = phase
        self.role = role
    }
}

public enum RealtimeExpression: String, Codable, Sendable, Equatable {
    case thinking
    case speaking
    case restore
}

public struct RealtimeEventEffects: Sendable, Equatable {
    public let transcript: RealtimeTranscriptUpdate?
    public let expression: RealtimeExpression?

    public init(transcript: RealtimeTranscriptUpdate? = nil, expression: RealtimeExpression? = nil) {
        self.transcript = transcript
        self.expression = expression
    }
}

public struct RealtimeEventInterpreter: Sendable {
    private var transcript = ""
    private var transcriptKey = ""
    private var userTranscript = ""
    private var userTranscriptKey = ""

    public init() {}

    public mutating func handle(data: Data) throws -> RealtimeEventEffects {
        let event = try JSONDecoder().decode(Event.self, from: data)
        return handle(event)
    }

    public mutating func reset() {
        transcript = ""
        transcriptKey = ""
        userTranscript = ""
        userTranscriptKey = ""
    }

    private mutating func handle(_ event: Event) -> RealtimeEventEffects {
        switch event.type {
        case "response.created":
            reset()
            return RealtimeEventEffects(expression: .thinking)
        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            let key = event.transcriptIdentifier
            if !key.isEmpty, key != transcriptKey {
                transcript = ""
                transcriptKey = key
            }
            transcript += event.delta ?? event.transcript ?? event.text ?? ""
            guard !transcript.isEmpty else {
                return RealtimeEventEffects(expression: .speaking)
            }
            return RealtimeEventEffects(
                transcript: RealtimeTranscriptUpdate(text: transcript, phase: .partial),
                expression: .speaking
            )
        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            let finalTranscript = event.transcript ?? event.text ?? transcript
            reset()
            return RealtimeEventEffects(
                transcript: finalTranscript.isEmpty ? nil : RealtimeTranscriptUpdate(text: finalTranscript, phase: .final),
                expression: .restore
            )
        case "conversation.item.input_audio_transcription.delta":
            let key = event.transcriptIdentifier
            if !key.isEmpty, key != userTranscriptKey {
                userTranscript = ""
                userTranscriptKey = key
            }
            userTranscript += event.delta ?? event.transcript ?? event.text ?? ""
            return RealtimeEventEffects(transcript: userTranscript.isEmpty ? nil : RealtimeTranscriptUpdate(
                text: userTranscript,
                phase: .partial,
                role: .user
            ))
        case "conversation.item.input_audio_transcription.completed":
            let finalTranscript = event.transcript ?? event.text ?? userTranscript
            userTranscript = ""
            userTranscriptKey = ""
            return RealtimeEventEffects(transcript: finalTranscript.isEmpty ? nil : RealtimeTranscriptUpdate(
                text: finalTranscript,
                phase: .final,
                role: .user
            ))
        case "response.done", "response.cancelled":
            reset()
            return RealtimeEventEffects(expression: .restore)
        default:
            return RealtimeEventEffects()
        }
    }
}

public struct RealtimeGhostManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let expressions: [RealtimeExpression: Int]

    public init(version: Int = 1, expressions: [RealtimeExpression: Int]) {
        self.version = version
        self.expressions = expressions.filter { $0.key != .restore }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        let values = try container.decode([String: Int].self, forKey: .expressions)
        expressions = Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
            guard let expression = RealtimeExpression(rawValue: key), expression != .restore else { return nil }
            return (expression, value)
        })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(
            Dictionary(uniqueKeysWithValues: expressions.map { ($0.key.rawValue, $0.value) }),
            forKey: .expressions
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case expressions
    }
}

public enum RealtimeGhostManifestLoader {
    public static let filename = "realtime.json"

    public static func loadIfPresent(masterDirectoryURL: URL) -> RealtimeGhostManifest? {
        let url = masterDirectoryURL.appending(path: filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RealtimeGhostManifest.self, from: data)
    }
}

private struct Event: Decodable {
    let type: String
    let responseID: String?
    let itemID: String?
    let segmentID: String?
    let contentIndex: Int?
    let delta: String?
    let transcript: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type
        case responseID = "response_id"
        case itemID = "item_id"
        case segmentID = "segment_id"
        case contentIndex = "content_index"
        case delta
        case transcript
        case text
    }

    var transcriptIdentifier: String {
        [responseID, itemID, segmentID, contentIndex.map(String.init)]
            .compactMap(\.self)
            .joined(separator: ":")
    }
}
