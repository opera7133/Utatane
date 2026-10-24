import Foundation
import Testing
@testable import UtataneNativeSaori

private struct FakeMediaInfoReader: InternalSaoriMediaReading {
    func read(_ url: URL) throws -> InternalSaoriMediaInfo {
        .init(kind: "audio", values: ["title": "a\r\nb\nc\0", "duration": "123", "filename": url.lastPathComponent])
    }
}

@Test func `MediaInfo honors ghost relative paths requested key order empty values and wire sanitizing`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "曲.mp3")
    try Data().write(to: file)
    let service = InternalSaoriService(ghostDirectory: root, mediaReader: FakeMediaInfoReader())
    func request(_ args: [String], service: InternalSaoriService = service) -> String {
        let wire = (["EXECUTE SAORI/1.0", "Charset: UTF-8", "Module: internal_file"] + args.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
        return String(decoding: service.response(to: Data(wire.utf8)), as: UTF8.self)
    }
    let response = request(["MediaInfo", "曲.mp3", "title", "unknown", "duration", "filename"])
    #expect(response.contains("Result: audio\r\nValue0: a\u{1}b\u{1}c\r\nValue1: \r\nValue2: 123\r\nValue3: 曲.mp3"))
    #expect(request(["MediaInfo", "曲.mp3"]).contains("invalid parameter"))
    #expect(request(["MediaInfo", "missing", "title"]).contains("file not found"))
    #expect(request(["MediaInfo", "https://example.com/a", "title"]).contains("file not found"))
    let noGhost = InternalSaoriService(mediaReader: FakeMediaInfoReader())
    #expect(request(["MediaInfo", "曲.mp3", "title"], service: noGhost).contains("ghost required"))
    #expect(request(["MediaInfo", file.path, "title"], service: noGhost).contains("Result: audio"))
    #expect(request(["MediaInfo", file.path, "title"], service: .init()).contains("unknown module"))
}
