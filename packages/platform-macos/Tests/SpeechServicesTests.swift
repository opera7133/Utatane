import Foundation
import Testing
@testable import UtatanePlatformMacOS

struct SpeechServicesTests {
    @Test
    func `VOICEVOX compatible API exposes flattened speakers and styles`() async throws {
        let client = VoicevoxEngineClient { request in
            let url = try #require(request.url)
            #expect(url.path == "/speakers")
            let data = try #require(#"""
            [
                {"name":"四国めたん","styles":[{"name":"ノーマル","id":2},{"name":"あまあま","id":0}]},
                {"name":"ずんだもん","styles":[{"name":"ノーマル","id":3}]}
            ]
            """#.data(using: .utf8))
            return (data, response(for: url))
        }

        let voices = try await client.voices(serviceURL: #require(URL(string: "http://127.0.0.1:50021")))

        #expect(Dictionary(uniqueKeysWithValues: voices.map { ($0.identifier, $0.name) }) == [
            "0": "四国めたん — あまあま",
            "2": "四国めたん — ノーマル",
            "3": "ずんだもん — ノーマル"
        ])
    }

    @Test
    func `VOICEVOX compatible synthesis adjusts common parameters`() async throws {
        let capture = RequestCapture()
        let client = VoicevoxEngineClient { request in
            let url = try #require(request.url)
            switch url.path {
            case "/audio_query":
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.queryItems?.first(where: { $0.name == "text" })?.value == "読み上げ")
                #expect(components.queryItems?.first(where: { $0.name == "speaker" })?.value == "7")
                let data = try #require(#"{"speedScale":1,"volumeScale":1,"pitchScale":0,"accent_phrases":[]}"#
                    .data(using: .utf8))
                return (data, response(for: url))
            case "/synthesis":
                await capture.store(request)
                return (Data("RIFF-test-wave".utf8), response(for: url, contentType: "audio/wav"))
            default:
                Issue.record("Unexpected endpoint: \(url)")
                return (Data(), response(for: url, statusCode: 404))
            }
        }
        let serviceURL = try #require(URL(string: "http://127.0.0.1:50021"))
        let request = SpeechSynthesisRequest(
            text: "読み上げ",
            scope: 0,
            configuration: SpeechSynthesisConfiguration(
                provider: .voicevoxCompatible,
                voiceIdentifier: "7",
                serviceURL: serviceURL,
                rate: 0.75,
                volume: 0.8,
                pitchMultiplier: 1.5
            )
        )

        let audio = try await client.synthesize(request)
        let synthesisRequest = try #require(await capture.request)
        let queryData = try #require(synthesisRequest.httpBody)
        let query = try #require(try JSONSerialization.jsonObject(with: queryData) as? [String: Any])

        #expect(audio == Data("RIFF-test-wave".utf8))
        #expect(query["speedScale"] as? Double == 1.5)
        #expect(abs((query["volumeScale"] as? Double ?? 0) - 0.8) < 0.000_001)
        #expect(query["pitchScale"] as? Double == 0.075)
        #expect(synthesisRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func `COEIROINK API exposes speaker UUID and style pairs`() async throws {
        let client = CoeiroinkEngineClient { request in
            let url = try #require(request.url)
            #expect(url.path == "/v1/speakers")
            let data = try #require(#"""
            [
                {
                    "speakerName":"つくよみちゃん",
                    "speakerUuid":"3c37646f-3881-5374-2a83-149267990abc",
                    "styles":[{"styleName":"れいせい","styleId":0},{"styleName":"おしとやか","styleId":5}]
                }
            ]
            """#.data(using: .utf8))
            return (data, response(for: url))
        }

        let voices = try await client.voices(serviceURL: #require(URL(string: "http://127.0.0.1:50032")))

        #expect(voices.count == 2)
        #expect(voices[0].groupIdentifier == "3c37646f-3881-5374-2a83-149267990abc")
        #expect(Set(voices.map(\.identifier)) == ["0", "5"])
        #expect(Set(voices.map(\.id)) == [
            "3c37646f-3881-5374-2a83-149267990abc:0",
            "3c37646f-3881-5374-2a83-149267990abc:5"
        ])
    }

    @Test
    func `COEIROINK synthesis sends its dedicated request format`() async throws {
        let capture = RequestCapture()
        let client = CoeiroinkEngineClient { request in
            await capture.store(request)
            let url = try #require(request.url)
            return (Data("RIFF-coeiroink-wave".utf8), response(for: url, contentType: "audio/wav"))
        }
        let serviceURL = try #require(URL(string: "http://127.0.0.1:50032"))
        let request = SpeechSynthesisRequest(
            text: "読み上げ",
            scope: 1,
            configuration: SpeechSynthesisConfiguration(
                provider: .coeiroink,
                voiceIdentifier: "5",
                voiceGroupIdentifier: "3c37646f-3881-5374-2a83-149267990abc",
                serviceURL: serviceURL,
                rate: 0.75,
                volume: 0.8,
                pitchMultiplier: 1.5
            )
        )

        let audio = try await client.synthesize(request)
        let synthesisRequest = try #require(await capture.request)
        let bodyData = try #require(synthesisRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(audio == Data("RIFF-coeiroink-wave".utf8))
        #expect(synthesisRequest.url?.path == "/v1/synthesis")
        #expect(body["speakerUuid"] as? String == "3c37646f-3881-5374-2a83-149267990abc")
        #expect(body["styleId"] as? Int == 5)
        #expect(body["text"] as? String == "読み上げ")
        #expect(body["speedScale"] as? Double == 1.5)
        #expect(abs((body["volumeScale"] as? Double ?? 0) - 0.8) < 0.000_001)
        #expect(body["pitchScale"] as? Double == 0.075)
        #expect(body["processingAlgorithm"] as? String == "coeiroink")
        #expect(synthesisRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test
    func `VOICEPEAK lists narrators from its command line API`() async throws {
        let capture = CommandCapture()
        let client = VoicepeakEngineClient { executableURL, arguments in
            await capture.store(executableURL: executableURL, arguments: arguments)
            return .init(standardOutput: Data("Japanese Female 1\n夏色花梨\n".utf8))
        }
        let executableURL = URL(fileURLWithPath: "/Applications/voicepeak.app/Contents/MacOS/voicepeak")

        let voices = try await client.voices(executableURL: executableURL)

        #expect(voices.map(\.identifier) == ["Japanese Female 1", "夏色花梨"])
        #expect(await capture.arguments == ["--list-narrator"])
    }

    @Test
    func `VOICEPEAK synthesis uses arguments without a shell`() async throws {
        let capture = CommandCapture()
        let client = VoicepeakEngineClient { executableURL, arguments in
            await capture.store(executableURL: executableURL, arguments: arguments)
            let outputIndex = try #require(arguments.firstIndex(of: "--out"))
            let outputPath = arguments[outputIndex + 1]
            try Data("RIFF-voicepeak-wave".utf8).write(to: URL(fileURLWithPath: outputPath))
            return .init(standardOutput: Data())
        }
        let executableURL = URL(fileURLWithPath: "/Applications/voicepeak.app/Contents/MacOS/voicepeak")
        let request = SpeechSynthesisRequest(
            text: "引用符も'シェル'へ渡さない",
            scope: 0,
            configuration: SpeechSynthesisConfiguration(
                provider: .voicepeak,
                voiceIdentifier: "夏色花梨",
                serviceURL: executableURL,
                rate: 0.75,
                volume: 0.8,
                pitchMultiplier: 1.5
            )
        )

        let audio = try await client.synthesize(request)
        let arguments = try #require(await capture.arguments)
        let sayIndex = try #require(arguments.firstIndex(of: "--say"))
        let narratorIndex = try #require(arguments.firstIndex(of: "--narrator"))
        let speedIndex = try #require(arguments.firstIndex(of: "--speed"))
        let pitchIndex = try #require(arguments.firstIndex(of: "--pitch"))

        #expect(audio == Data("RIFF-voicepeak-wave".utf8))
        #expect(arguments[sayIndex + 1] == "引用符も'シェル'へ渡さない")
        #expect(arguments[narratorIndex + 1] == "夏色花梨")
        #expect(arguments[speedIndex + 1] == "150")
        #expect(arguments[pitchIndex + 1] == "150")
    }
}

private actor RequestCapture {
    private(set) var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }
}

private actor CommandCapture {
    private(set) var executableURL: URL?
    private(set) var arguments: [String]?

    func store(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

private func response(
    for url: URL,
    statusCode: Int = 200,
    contentType: String = "application/json"
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}
