import Foundation
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript

private func httpCommand(_ parameters: [String] = [], type: String? = nil, options: [String] = [], method: String = "POST") -> SakuraScriptHTTPRequest {
    .init(method: method, url: "http://localhost/api?q=old", eventID: "OnDone", waitsForCompletion: false, parameters: parameters,
          options: options, headers: type.map { ["Content-Type: \($0)"] } ?? [], output: .memory(characterEncoding: nil))
}

@Test func `HTTP body builder follows form raw and multipart contracts`() throws {
    let root = FileManager.default.temporaryDirectory
    let form = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["a=1", "b=2"]), masterDirectory: root)
    #expect(form.request.httpBody == Data("a=1&b=2".utf8))
    let legacy = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["legacy", "second"]), masterDirectory: root)
    #expect(legacy.request.httpBody == Data("legacy\r\nsecond".utf8))
    let json = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["one", "two"], type: "application/json"), masterDirectory: root)
    #expect(json.request.httpBody == Data("one\r\ntwo".utf8))
    let multi = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["a=日本語", "a=x=y", "empty="], type: "multipart/form-data"), masterDirectory: root, boundary: "fixture")
    let expected = "--fixture\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n日本語\r\n--fixture\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nx=y\r\n--fixture\r\nContent-Disposition: form-data; name=\"empty\"\r\n\r\n\r\n--fixture--\r\n"
    #expect(multi.request.httpBody == Data(expected.utf8))
    #expect(multi.request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=\"fixture\"")
    let sjis = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["a=あ"], type: "multipart/form-data", options: ["--param-charset=Shift_JIS"]), masterDirectory: root, boundary: "fixture")
    #expect(sjis.request.httpBody?.range(of: Data([0x82, 0xA0])) != nil)
    let get = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["name=日本語", "percent=%20&bad=%q"], method: "GET"), masterDirectory: root)
    #expect(get.request.url?.absoluteString == "http://localhost/api?q=old&name=%E6%97%A5%E6%9C%AC%E8%AA%9E&percent=%20&bad=%25q")
    #expect(get.request.httpBody == nil)
}

@Test func `HTTP file bodies are streamed and preserve the multipart boundary`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "送信.bin")
    let body = Data("--file-boundary\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.bin\"\r\n\r\n".utf8) + Data([0, 255, 1]) + Data("\r\n--file-boundary--\r\n".utf8)
    try body.write(to: file)
    let prepared = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(type: "multipart/form-data", options: ["--param-input-file=送信.bin"]), masterDirectory: root)
    #expect(prepared.bodyFileURL == file.resolvingSymlinksInPath())
    #expect(prepared.request.httpBody == nil)
    #expect(prepared.request.httpBodyStream != nil)
    #expect(prepared.request.value(forHTTPHeaderField: "Content-Length") == String(body.count))
    #expect(prepared.request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=\"file-boundary\"")
    #expect(throws: (any Error).self) {
        try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(["a=1"], options: ["--param-input-file=送信.bin"]), masterDirectory: root)
    }
    #expect(throws: (any Error).self) {
        try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(type: "multipart/form-data; boundary=other", options: ["--param-input-file=送信.bin"]), masterDirectory: root)
    }
    let raw = try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(type: "application/octet-stream", options: ["--param-input-file=送信.bin"]), masterDirectory: root)
    #expect(raw.request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
    let outside = root.deletingLastPathComponent().appending(path: UUID().uuidString)
    try body.write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: outside)
    for input in [outside.path, "escape", "missing"] {
        #expect(throws: (any Error).self) {
            try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(options: ["--param-input-file=\(input)"]), masterDirectory: root)
        }
    }
}

@Test func `HTTP requests do not share default output files and reject MIME header injection`() throws {
    let root = FileManager.default.temporaryDirectory
    let command = SakuraScriptHTTPRequest(method: "GET", url: "https://example.com/a.bin", eventID: nil, waitsForCompletion: false)
    let first = try #require(SakuraScriptHTTPRequestBuilder.destination(command, masterDirectory: root, invocationID: UUID()))
    let second = try #require(SakuraScriptHTTPRequestBuilder.destination(command, masterDirectory: root, invocationID: UUID()))
    #expect(first != second)
    #expect(first.lastPathComponent.hasSuffix("-a.bin"))
    let injected = SakuraScriptHTTPRequest(method: "POST", url: "http://localhost/", eventID: nil, waitsForCompletion: false,
                                           headers: ["X-Field: value\r\nOther: injected"])
    #expect(throws: (any Error).self) { try SakuraScriptHTTPRequestBuilder.prepare(injected, masterDirectory: root) }
    for parameters in [["a\r\nHeader: bad=x"], ["no separator"], ["x=--fixture"]] {
        #expect(throws: (any Error).self) {
            try SakuraScriptHTTPRequestBuilder.prepare(httpCommand(parameters, type: "multipart/form-data"), masterDirectory: root, boundary: "fixture")
        }
    }
}
