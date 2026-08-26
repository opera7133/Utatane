import Foundation
import Testing
@testable import UtataneRealtime

@Test func `normalizes OpenAI and compatible call URLs`() throws {
    #expect(try RealtimeCallRequestBuilder.callsURL(baseURL: #require(URL(string: "https://api.openai.com"))).absoluteString == "https://api.openai.com/v1/realtime/calls")
    #expect(try RealtimeCallRequestBuilder.callsURL(baseURL: #require(URL(string: "https://example.test/v1"))).absoluteString == "https://example.test/v1/realtime/calls")
    #expect(try RealtimeCallRequestBuilder.callsURL(baseURL: #require(URL(string: "https://example.test/v1/realtime/calls"))).absoluteString == "https://example.test/v1/realtime/calls")
}

@Test func `builds OpenAI-compatible multipart call`() throws {
    let request = try RealtimeCallRequestBuilder.make(
        baseURL: #require(URL(string: "https://example.test")),
        model: "model",
        voice: "character",
        offerSDP: "v=0\r\n",
        boundary: "test-boundary"
    )
    let body = String(decoding: request.body, as: UTF8.self)
    #expect(request.contentType == "multipart/form-data; boundary=test-boundary")
    #expect(body.contains("name=\"sdp\""))
    #expect(body.contains("v=0\r\n"))
    #expect(body.contains("name=\"session\""))
    #expect(body.contains("\"model\":\"model\""))
    #expect(body.contains("\"voice\":\"character\""))
    #expect(body.hasSuffix("--test-boundary--\r\n"))
}

@Test func `accumulates transcript deltas and finalizes with done text`() throws {
    var interpreter = RealtimeEventInterpreter()

    let started = try interpreter.handle(data: Data(#"{"type":"response.created"}"#.utf8))
    #expect(started.expression == .thinking)

    let first = try interpreter.handle(data: Data(#"{"type":"response.output_audio_transcript.delta","response_id":"r1","item_id":"i1","delta":"こん"}"#.utf8))
    #expect(first.transcript == RealtimeTranscriptUpdate(text: "こん", phase: .partial))
    #expect(first.expression == .speaking)

    let second = try interpreter.handle(data: Data(#"{"type":"response.output_audio_transcript.delta","response_id":"r1","item_id":"i1","delta":"にちは"}"#.utf8))
    #expect(second.transcript == RealtimeTranscriptUpdate(text: "こんにちは", phase: .partial))

    let done = try interpreter.handle(data: Data(#"{"type":"response.output_audio_transcript.done","response_id":"r1","item_id":"i1","transcript":"こんにちは。"}"#.utf8))
    #expect(done.transcript == RealtimeTranscriptUpdate(text: "こんにちは。", phase: .final))
    #expect(done.expression == .restore)
}

@Test func `supports compatible transcript fields and resets between segments`() throws {
    var interpreter = RealtimeEventInterpreter()

    let first = try interpreter.handle(data: Data(#"{"type":"response.audio_transcript.delta","segment_id":"a","text":"A"}"#.utf8))
    #expect(first.transcript?.text == "A")

    let next = try interpreter.handle(data: Data(#"{"type":"response.audio_transcript.delta","segment_id":"b","text":"B"}"#.utf8))
    #expect(next.transcript?.text == "B")

    let done = try interpreter.handle(data: Data(#"{"type":"response.audio_transcript.done","segment_id":"b"}"#.utf8))
    #expect(done.transcript?.text == "B")
    #expect(done.transcript?.phase == .final)
}

@Test func `accumulates user input transcription`() throws {
    var interpreter = RealtimeEventInterpreter()
    let partial = try interpreter.handle(data: Data(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"u1","delta":"テスト"}"#.utf8))
    #expect(partial.transcript == RealtimeTranscriptUpdate(text: "テスト", phase: .partial, role: .user))
    let done = try interpreter.handle(data: Data(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"u1","transcript":"テストです"}"#.utf8))
    #expect(done.transcript == RealtimeTranscriptUpdate(text: "テストです", phase: .final, role: .user))
}

@Test func `loads only ghost-declared realtime expression surfaces`() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data(#"{"version":1,"expressions":{"thinking":9,"speaking":0}}"#.utf8)
        .write(to: directory.appending(path: RealtimeGhostManifestLoader.filename))

    let manifest = try #require(RealtimeGhostManifestLoader.loadIfPresent(masterDirectoryURL: directory))
    #expect(manifest.expressions == [.thinking: 9, .speaking: 0])
    #expect(manifest.expressions[.restore] == nil)
}
