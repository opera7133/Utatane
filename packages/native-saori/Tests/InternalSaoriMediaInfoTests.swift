import Foundation
import Testing
import UtataneCore
@testable import UtataneNativeSaori

private struct FakeMediaInfoReader: InternalSaoriMediaReading {
    func read(_ url: URL) throws -> InternalSaoriMediaInfo {
        .init(kind: "audio", values: ["title": "a\r\nb\nc\0", "duration": "123", "filename": url.lastPathComponent])
    }
}

private struct ImageCapabilityReader: InternalSaoriMediaReading {
    func read(_: URL) throws -> InternalSaoriMediaInfo {
        .init(kind: "audio")
    }

    func imageInfo(_ url: URL) throws -> InternalSaoriMediaInfo {
        url.pathExtension == "png" ? .init(kind: "image", values: ["width": "3", "height": "2", "secret": "not a standard key"]) : .init()
    }

    func imageLoadability(_ url: URL) throws -> InternalSaoriLoadability {
        url.pathExtension == "png" ? .write : .none
    }

    func mediaLoadability(_ url: URL) throws -> InternalSaoriLoadability {
        url.pathExtension == "wav" ? .read : .none
    }
}

@Test func `image information and loadability follow file argument and wire contracts`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "画像 日本語 \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
    for file in ["sub/絵.png", "音.wav", "unknown.bin"] {
        try Data().write(to: root.appending(path: file))
    }
    let service = InternalSaoriService(ghostDirectory: root, mediaReader: ImageCapabilityReader())
    func response(_ args: [String], charset: String = "UTF-8", instance: InternalSaoriService = service) throws -> String {
        let wire = (["EXECUTE SAORI/1.0", "Charset: \(charset)", "Module: internal_file"] + args.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
        let encoded = try #require(LegacyTextDecoder.encode(wire, charset: charset == "Shift_JIS" ? "CP932" : charset))
        return try #require(LegacyTextDecoder.decode(instance.response(to: encoded), preferredCharset: charset))
    }
    let image = try response(["ImageInfo", "sub\\絵.png", "HEIGHT", "secret", "width", "width"], charset: "Shift_JIS")
    #expect(image.contains("Result: image\r\nValue0: 2\r\nValue1: \r\nValue2: 3\r\nValue3: 3"))
    #expect(try response(["ImageInfo", "音.wav", "width", "height"]).hasPrefix("SAORI/1.0 200"))
    #expect(try response(["ImageInfo", "音.wav", "width", "height"]).contains("Result: \r\nValue0: \r\nValue1: \r\n"))
    #expect(try response(["IsImageLoadable", "sub/絵.png"]).contains("Result: write\r\n"))
    #expect(try response(["IsMediaLoadable", "音.wav"]).contains("Result: read\r\n"))
    #expect(try response(["IsImageLoadable", "unknown.bin"]).contains("Result: none\r\n"))
    for args in [["ImageInfo", "sub/絵.png"], ["IsMediaLoadable"], ["IsImageLoadable", "sub/絵.png", "extra"],
                 ["ImageInfo", "sub/絵.png"] + Array(repeating: "width", count: 12)]
    {
        #expect(try response(args).contains("invalid parameter"))
    }
    for file in ["sub", "missing", "https://example.invalid/image.png"] {
        #expect(try response(["IsImageLoadable", file]).contains("file not found"))
    }
    let noGhost = InternalSaoriService(mediaReader: ImageCapabilityReader())
    #expect(try response(["IsImageLoadable", "sub/絵.png"], instance: noGhost).contains("ghost required"))
    #expect(try response(["IsImageLoadable", root.appending(path: "sub/絵.png").path], instance: noGhost).contains("Result: write"))
    #expect(InternalSaoriService.positionalCount(module: "internal_file", function: "IsMediaLoadable") == 1)
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
