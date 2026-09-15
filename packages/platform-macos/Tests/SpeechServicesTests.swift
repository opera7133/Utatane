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

    @Test
    func `VoiSona Talk lists every installed voice language`() async throws {
        let capture = RequestCapture()
        let credential = SpeechCredentialStore.Credential(
            username: "speaker@example.com",
            password: "api-secret"
        )
        let client = VoiSonaTalkEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                let data = try #require(#"""
                {
                  "items": [
                    {
                      "display_names": [
                        {"language":"ja_JP","name":"田中さん"},
                        {"language":"en_US","name":"Tanaka-san"}
                      ],
                      "languages": ["ja_JP", "en_US"],
                      "voice_name": "tanaka-san",
                      "voice_version": "2.0.1"
                    }
                  ]
                }
                """#.data(using: .utf8))
                return (data, response(for: url))
            },
            credentialProvider: { _ in credential }
        )

        let voices = try await client.voices(
            serviceURL: #require(URL(string: "http://127.0.0.1:32766/api/talk/v1")),
            credential: credential
        )

        #expect(voices.map(\.id) == [
            "2.0.1:tanaka-san:en_US",
            "2.0.1:tanaka-san:ja_JP"
        ])
        #expect(voices.map(\.name) == ["Tanaka-san", "田中さん"])
        #expect(await capture.request?.url?.path == "/api/talk/v1/voices")
        #expect(await capture.request?.value(forHTTPHeaderField: "Authorization") ==
            "Basic c3BlYWtlckBleGFtcGxlLmNvbTphcGktc2VjcmV0")
    }

    @Test
    func `VoiSona Talk writes a temporary WAV and retires its job`() async throws {
        let capture = RequestSequenceCapture()
        let credential = SpeechCredentialStore.Credential(
            username: "speaker@example.com",
            password: "api-secret"
        )
        let client = VoiSonaTalkEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                switch (request.httpMethod ?? "GET", url.path) {
                case ("POST", "/api/talk/v1/speech-syntheses"):
                    let bodyData = try #require(request.httpBody)
                    let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
                    let outputPath = try #require(body["output_file_path"] as? String)
                    try Data("RIFF-voisona-wave".utf8).write(to: URL(fileURLWithPath: outputPath))
                    return (Data(#"{"uuid":"job-123"}"#.utf8), response(for: url))
                case ("GET", "/api/talk/v1/speech-syntheses/job-123"):
                    return (Data(#"{"state":"succeeded"}"#.utf8), response(for: url))
                case ("DELETE", "/api/talk/v1/speech-syntheses/job-123"):
                    return (Data(), response(for: url))
                default:
                    Issue.record("Unexpected endpoint: \(request.httpMethod ?? "GET") \(url.path)")
                    return (Data(), response(for: url, statusCode: 404))
                }
            },
            sleeper: {},
            credentialProvider: { scope in
                #expect(scope == 1)
                return credential
            }
        )
        let serviceURL = try #require(URL(string: "http://localhost:32766/api/talk/v1"))
        let request = SpeechSynthesisRequest(
            text: "読み上げ",
            scope: 1,
            configuration: SpeechSynthesisConfiguration(
                provider: .voisonaTalk,
                voiceIdentifier: "tanaka-san",
                voiceGroupIdentifier: "2.0.1",
                voiceLanguageIdentifier: "ja_JP",
                serviceURL: serviceURL,
                rate: 0.75,
                volume: 0.8,
                pitchMultiplier: 1.5
            )
        )

        let audio = try await client.synthesize(request)
        let requests = await capture.requests
        let createBodyData = try #require(requests.first?.httpBody)
        let createBody = try #require(try JSONSerialization.jsonObject(with: createBodyData) as? [String: Any])
        let parameters = try #require(createBody["global_parameters"] as? [String: Any])

        #expect(audio == Data("RIFF-voisona-wave".utf8))
        #expect(requests.map { $0.httpMethod ?? "GET" } == ["POST", "GET", "DELETE"])
        #expect(createBody["destination"] as? String == "file")
        #expect(createBody["voice_name"] as? String == "tanaka-san")
        #expect(createBody["voice_version"] as? String == "2.0.1")
        #expect(createBody["language"] as? String == "ja_JP")
        #expect(parameters["speed"] as? Double == 1.5)
        #expect(parameters["pitch"] as? Double == 300)
    }

    @Test
    func `VoiSona Talk credentials never leave the loopback host`() async throws {
        let client = VoiSonaTalkEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _ in
                SpeechCredentialStore.Credential(username: "user", password: "secret")
            }
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.voices(
                serviceURL: #require(URL(string: "https://example.com/api/talk/v1")),
                credential: SpeechCredentialStore.Credential(username: "user", password: "secret")
            )
        }
        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.voices(
                serviceURL: #require(URL(string: "https://127.attacker.example/api/talk/v1")),
                credential: SpeechCredentialStore.Credential(username: "user", password: "secret")
            )
        }
    }

    @Test
    func `OpenAI synthesis sends its current speech request format`() async throws {
        let capture = RequestCapture()
        let client = OpenAISpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (Data("RIFF-openai-wave".utf8), response(for: url, contentType: "audio/wav"))
            },
            credentialProvider: { provider, scope in
                #expect(provider == .openAI)
                #expect(scope == 1)
                return SpeechCredentialStore.Credential(password: "test-api-key")
            }
        )
        let request = SpeechSynthesisRequest(
            text: " 雨が降りそう。 ",
            scope: 1,
            configuration: SpeechSynthesisConfiguration(
                provider: .openAI,
                voiceIdentifier: "marin",
                serviceURL: URL(string: "https://api.openai.com/v1"),
                modelIdentifier: "gpt-4o-mini-tts",
                instructions: "落ち着いた声で",
                rate: 0.75,
                volume: 0.8
            )
        )

        let audio = try await client.synthesize(request)
        let synthesisRequest = try #require(await capture.request)
        let bodyData = try #require(synthesisRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(audio == Data("RIFF-openai-wave".utf8))
        #expect(synthesisRequest.url?.absoluteString == "https://api.openai.com/v1/audio/speech")
        #expect(synthesisRequest.httpMethod == "POST")
        #expect(synthesisRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(synthesisRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["model"] as? String == "gpt-4o-mini-tts")
        #expect(body["input"] as? String == "雨が降りそう。")
        #expect(body["voice"] as? String == "marin")
        #expect(body["instructions"] as? String == "落ち着いた声で")
        #expect(body["response_format"] as? String == "wav")
        #expect(body["speed"] as? Double == 1.5)
    }

    @Test
    func `OpenAI credentials can only be sent to its HTTPS API`() async throws {
        let client = OpenAISpeechEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _, _ in
                SpeechCredentialStore.Credential(password: "test-api-key")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .openAI,
            voiceIdentifier: "marin",
            serviceURL: URL(string: "https://example.com/v1"),
            modelIdentifier: "gpt-4o-mini-tts"
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }

    @Test
    func `OpenAI compatible local synthesis stays on loopback and allows optional auth`() async throws {
        let capture = RequestCapture()
        let client = OpenAISpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (Data("RIFF-irodori-wave".utf8), response(for: url, contentType: "audio/wav"))
            },
            credentialProvider: { provider, scope in
                #expect(provider == .openAICompatibleLocal)
                #expect(scope == 0)
                return SpeechCredentialStore.Credential()
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .openAICompatibleLocal,
            voiceIdentifier: "none",
            serviceURL: URL(string: "http://localhost:8088/v1"),
            modelIdentifier: "irodori-tts"
        )

        let audio = try await client.synthesize(.init(text: "ローカル合成", scope: 0, configuration: configuration))
        let synthesisRequest = try #require(await capture.request)

        #expect(audio == Data("RIFF-irodori-wave".utf8))
        #expect(synthesisRequest.url?.absoluteString == "http://localhost:8088/v1/audio/speech")
        #expect(synthesisRequest.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func `OpenAI compatible local credentials never leave the loopback host`() async throws {
        let client = OpenAISpeechEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _, _ in
                SpeechCredentialStore.Credential(password: "local-token")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .openAICompatibleLocal,
            voiceIdentifier: "none",
            serviceURL: URL(string: "http://192.168.1.20:8088/v1"),
            modelIdentifier: "irodori-tts"
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }

    @Test
    func `ElevenLabs lists every paged voice`() async throws {
        let capture = RequestSequenceCapture()
        let client = ElevenLabsEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let nextToken = components.queryItems?.first(where: { $0.name == "next_page_token" })?.value
                if nextToken == nil {
                    return (
                        Data(#"{"voices":[{"voice_id":"voice-b","name":"Beta","verified_languages":[{"language":"ja"}]}],"has_more":true,"next_page_token":"page-2"}"#.utf8),
                        response(for: url)
                    )
                }
                #expect(nextToken == "page-2")
                return (
                    Data(#"{"voices":[{"voice_id":"voice-a","name":"Alpha","verified_languages":[]}],"has_more":false}"#.utf8),
                    response(for: url)
                )
            },
            credentialProvider: { scope in
                #expect(scope == 0)
                return SpeechCredentialStore.Credential(password: "eleven-key")
            }
        )

        let voices = try await client.voices(scope: 0)
        let requests = await capture.requests

        #expect(voices.map(\.identifier) == ["voice-a", "voice-b"])
        #expect(voices.last?.language == "ja")
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path == "/v2/voices" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "xi-api-key") == "eleven-key" })
    }

    @Test
    func `ElevenLabs synthesis sends model voice and speed`() async throws {
        let capture = RequestCapture()
        let client = ElevenLabsEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (Data("ID3-elevenlabs-audio".utf8), response(for: url, contentType: "audio/mpeg"))
            },
            credentialProvider: { _ in
                SpeechCredentialStore.Credential(password: "eleven-key")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .elevenLabs,
            voiceIdentifier: "voice/with slash",
            serviceURL: URL(string: "https://api.elevenlabs.io/v1"),
            modelIdentifier: "eleven_multilingual_v2",
            rate: 0.75,
            volume: 0.7
        )

        let audio = try await client.synthesize(.init(text: " 読み上げ ", scope: 1, configuration: configuration))
        let synthesisRequest = try #require(await capture.request)
        let bodyData = try #require(synthesisRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let voiceSettings = try #require(body["voice_settings"] as? [String: Any])
        let components = try #require(synthesisRequest.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        })

        #expect(audio == Data("ID3-elevenlabs-audio".utf8))
        #expect(components.path == "/v1/text-to-speech/voice/with slash")
        #expect(components.queryItems == [URLQueryItem(name: "output_format", value: "mp3_44100_128")])
        #expect(synthesisRequest.value(forHTTPHeaderField: "xi-api-key") == "eleven-key")
        #expect(body["text"] as? String == "読み上げ")
        #expect(body["model_id"] as? String == "eleven_multilingual_v2")
        #expect(voiceSettings["speed"] as? Double == 1.5)
    }

    @Test
    func `Aivis Cloud synthesis sends model style and common controls`() async throws {
        let capture = RequestCapture()
        let client = AivisCloudEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (Data("ID3-aivis-audio".utf8), response(for: url, contentType: "audio/mpeg"))
            },
            credentialProvider: { scope in
                #expect(scope == 1)
                return SpeechCredentialStore.Credential(password: "aivis-key")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .aivisCloud,
            voiceIdentifier: "model-uuid",
            voiceGroupIdentifier: "speaker-uuid",
            serviceURL: URL(string: "https://api.aivis-project.com/v1"),
            styleIdentifier: "7",
            rate: 0.75,
            volume: 0.7,
            pitchMultiplier: 1.5
        )

        let audio = try await client.synthesize(.init(text: " 読み上げ ", scope: 1, configuration: configuration))
        let synthesisRequest = try #require(await capture.request)
        let bodyData = try #require(synthesisRequest.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        #expect(audio == Data("ID3-aivis-audio".utf8))
        #expect(synthesisRequest.url?.path == "/v1/tts/synthesize")
        #expect(synthesisRequest.value(forHTTPHeaderField: "Authorization") == "Bearer aivis-key")
        #expect(body["model_uuid"] as? String == "model-uuid")
        #expect(body["speaker_uuid"] as? String == "speaker-uuid")
        #expect(body["style_id"] as? Int == 7)
        #expect(body["text"] as? String == "読み上げ")
        #expect(body["use_ssml"] as? Bool == false)
        #expect(body["speaking_rate"] as? Double == 1.5)
        #expect(body["pitch"] as? Double == 0.5)
        #expect(body["output_format"] as? String == "mp3")
        #expect(body["leading_silence_seconds"] as? Double == 0)
    }

    @Test
    func `Aivis Cloud credentials never leave the official host`() async throws {
        let client = AivisCloudEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _ in
                SpeechCredentialStore.Credential(password: "aivis-key")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .aivisCloud,
            voiceIdentifier: "model-uuid",
            serviceURL: URL(string: "https://example.com/v1")
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }

    @Test
    func `Azure Speech lists regional voices`() async throws {
        let capture = RequestCapture()
        let client = AzureSpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (
                    Data(#"[{"ShortName":"ja-JP-NanamiNeural","LocalName":"七海","Locale":"ja-JP"}]"#.utf8),
                    response(for: url)
                )
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "azure-key") }
        )
        let serviceURL = try #require(URL(string: "https://japaneast.tts.speech.microsoft.com"))

        let voices = try await client.voices(serviceURL: serviceURL, scope: 0)
        let request = try #require(await capture.request)

        #expect(voices.map(\.identifier) == ["ja-JP-NanamiNeural"])
        #expect(voices.first?.languageIdentifier == "ja-JP")
        #expect(request.url?.path == "/cognitiveservices/voices/list")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "azure-key")
    }

    @Test
    func `Azure Speech sends escaped SSML and common controls`() async throws {
        let capture = RequestCapture()
        let client = AzureSpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (Data("ID3-azure-audio".utf8), response(for: url, contentType: "audio/mpeg"))
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "azure-key") }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .azureSpeech,
            voiceIdentifier: "ja-JP-NanamiNeural",
            voiceLanguageIdentifier: "ja-JP",
            serviceURL: URL(string: "https://japaneast.tts.speech.microsoft.com"),
            rate: 0.75,
            volume: 0.8,
            pitchMultiplier: 1.5
        )

        let audio = try await client.synthesize(.init(text: "A & B < C", scope: 0, configuration: configuration))
        let request = try #require(await capture.request)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(audio == Data("ID3-azure-audio".utf8))
        #expect(request.url?.path == "/cognitiveservices/v1")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "azure-key")
        #expect(request.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "audio-24khz-48kbitrate-mono-mp3")
        #expect(body.contains("name='ja-JP-NanamiNeural'"))
        #expect(body.contains("rate='150%'"))
        #expect(body.contains("pitch='+50%'"))
        #expect(body.contains("A &amp; B &lt; C"))
    }

    @Test
    func `Azure Speech credentials stay on a regional Microsoft host`() async throws {
        let client = AzureSpeechEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "azure-key") }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .azureSpeech,
            voiceIdentifier: "ja-JP-NanamiNeural",
            serviceURL: URL(string: "https://japaneast.tts.speech.microsoft.com.example.com")
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }

    @Test
    func `Google Cloud lists every voice language without putting its key in the URL`() async throws {
        let capture = RequestCapture()
        let client = GoogleCloudSpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (
                    Data(#"{"voices":[{"languageCodes":["ja-JP","en-US"],"name":"ja-JP-TestVoice"}]}"#.utf8),
                    response(for: url)
                )
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "google-key") }
        )

        let voices = try await client.voices(scope: 1)
        let request = try #require(await capture.request)

        #expect(voices.map(\.language).sorted() == ["en-US", "ja-JP"])
        #expect(request.url?.absoluteString == "https://texttospeech.googleapis.com/v1/voices")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "google-key")
    }

    @Test
    func `Google Cloud synthesis decodes audio and sends voice controls`() async throws {
        let capture = RequestCapture()
        let expectedAudio = Data("ID3-google-audio".utf8)
        let client = GoogleCloudSpeechEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                let data = try JSONEncoder().encode(["audioContent": expectedAudio.base64EncodedString()])
                return (data, response(for: url))
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "google-key") }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .googleCloudTTS,
            voiceIdentifier: "ja-JP-TestVoice",
            voiceLanguageIdentifier: "ja-JP",
            serviceURL: URL(string: "https://texttospeech.googleapis.com/v1"),
            rate: 0.75,
            volume: 0.8,
            pitchMultiplier: 1.5
        )

        let audio = try await client.synthesize(.init(text: " 読み上げ ", scope: 0, configuration: configuration))
        let request = try #require(await capture.request)
        let bodyData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let voice = try #require(body["voice"] as? [String: Any])
        let audioConfig = try #require(body["audioConfig"] as? [String: Any])

        #expect(audio == expectedAudio)
        #expect(request.url?.path == "/v1/text:synthesize")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "google-key")
        #expect((body["input"] as? [String: Any])?["text"] as? String == "読み上げ")
        #expect(voice["name"] as? String == "ja-JP-TestVoice")
        #expect(voice["languageCode"] as? String == "ja-JP")
        #expect(audioConfig["audioEncoding"] as? String == "MP3")
        #expect(audioConfig["speakingRate"] as? Double == 1.5)
        #expect(audioConfig["pitch"] as? Double == 6)
    }

    @Test
    func `Google Cloud credentials stay on the official API host`() async throws {
        let client = GoogleCloudSpeechEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _ in SpeechCredentialStore.Credential(password: "google-key") }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .googleCloudTTS,
            voiceIdentifier: "ja-JP-TestVoice",
            serviceURL: URL(string: "https://example.com/v1")
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }

    @Test
    func `AITalk WebAPI sends credentials and voice controls as form data`() async throws {
        let capture = RequestCapture()
        let expectedAudio = Data("ID3-aitalk-audio".utf8)
        let client = AITalkWebAPIEngineClient(
            transport: { request in
                await capture.store(request)
                let url = try #require(request.url)
                return (expectedAudio, response(for: url, contentType: "audio/mpeg"))
            },
            credentialProvider: { _ in
                SpeechCredentialStore.Credential(username: "contract-user", password: "contract+pass")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .aiTalkWebAPI,
            voiceIdentifier: "nozomi_dnn",
            serviceURL: URL(string: "https://webapi.aitalk.jp/webapi/v5"),
            rate: 0.75,
            volume: 0.8,
            pitchMultiplier: 1.5
        )

        let audio = try await client.synthesize(.init(text: " 読み上げ + & 確認 ", scope: 1, configuration: configuration))
        let request = try #require(await capture.request)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = Dictionary(
            uniqueKeysWithValues: (URLComponents(string: "?\(body)")?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )

        #expect(audio == expectedAudio)
        #expect(request.url?.absoluteString == "https://webapi.aitalk.jp/webapi/v5/ttsget.php")
        #expect(request.value(forHTTPHeaderField: "Content-Type") ==
            "application/x-www-form-urlencoded; charset=utf-8")
        #expect(fields["username"] == "contract-user")
        #expect(fields["password"] == "contract+pass")
        #expect(fields["speaker_name"] == "nozomi_dnn")
        #expect(fields["input_type"] == "text")
        #expect(fields["text"] == "読み上げ + & 確認")
        #expect(fields["ext"] == "mp3")
        #expect(fields["fs"] == "auto")
        #expect(fields["speed"] == "1.50")
        #expect(fields["pitch"] == "1.50")
        #expect(fields["tpause"] == "0")
    }

    @Test
    func `AITalk WebAPI credentials stay on the official endpoint`() async throws {
        let client = AITalkWebAPIEngineClient(
            transport: { request in
                Issue.record("Transport should not receive \(String(describing: request.url))")
                throw SpeechServiceError.invalidServiceResponse
            },
            credentialProvider: { _ in
                SpeechCredentialStore.Credential(username: "contract-user", password: "contract-pass")
            }
        )
        let configuration = SpeechSynthesisConfiguration(
            provider: .aiTalkWebAPI,
            voiceIdentifier: "nozomi_dnn",
            serviceURL: URL(string: "https://webapi.aitalk.jp.example.com/webapi/v5")
        )

        await #expect(throws: SpeechServiceError.invalidServiceURL) {
            try await client.synthesize(.init(text: "test", scope: 0, configuration: configuration))
        }
    }
}

private actor RequestCapture {
    private(set) var request: URLRequest?

    func store(_ request: URLRequest) {
        self.request = request
    }
}

private actor RequestSequenceCapture {
    private(set) var requests: [URLRequest] = []

    func store(_ request: URLRequest) {
        requests.append(request)
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
