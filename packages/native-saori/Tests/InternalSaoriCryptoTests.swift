import Darwin
import Foundation
import Testing
@testable import UtataneNativeSaori

private func cryptoResponse(_ service: InternalSaoriService, _ arguments: [String]) -> String {
    let wire = (["EXECUTE SAORI/1.0", "Charset: UTF-8", "Module: internal_crypto"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
    return String(decoding: service.response(to: Data(wire.utf8)), as: UTF8.self)
}

private func cryptoResponse(_ arguments: [String]) -> String {
    cryptoResponse(.init(), arguments)
}

@Test func `crypto Compare decodes signatures but forbids file and output options`() {
    for (a, b, expected) in [("", "", "1"), ("abc", "abc", "1"), ("abc", "abd", "0"), ("abc", "xbc", "0"), ("abc", "ab", "0")] {
        #expect(cryptoResponse(["Compare", a, b]).contains("Result: \(expected)\r\n"))
    }
    #expect(cryptoResponse(["Compare", "aBcD", "abcd", "--a-in=hex", "--b-in=hex"]).contains("Result: 1"))
    #expect(cryptoResponse(["Compare", "AP8=", "00ff", "--a-in=base64", "--b-in=hex"]).contains("Result: 1"))
    #expect(cryptoResponse(["Compare", "ab", "00", "--a-in=file"]).contains("unsupported algorithm"))
    #expect(cryptoResponse(["Compare", "ab", "ab", "--out=hex"]).contains("invalid parameter"))
    #expect(cryptoResponse(["Compare", "z", "00", "--a-in=hex"]).contains("invalid encoding"))
    #expect(cryptoResponse(["Compare", "a"]).contains("invalid parameter"))
}

@Test func `crypto file input streams past the message limit and resolves ghost paths`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let directory = root.appending(path: "素材")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = directory.appending(path: "大きい ファイル.bin")
    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    let chunk = Data((0 ..< 65536).map { UInt8(truncatingIfNeeded: $0) })
    for _ in 0 ..< 129 {
        try handle.write(contentsOf: chunk)
    }
    try handle.close()
    let service = InternalSaoriService(ghostDirectory: root)
    let relative = "素材\\大きい ファイル.bin"
    // Independent Python hashlib/hmac vectors for 129 repetitions of bytes(0..255)*256.
    #expect(cryptoResponse(service, ["Digest", "sha256", relative, "--data-in=file"]).contains("Result: 994e06a582608c2c12f2643ff10d0d45ce290f4b394291c2fb7707d3d11a21d9\r\n"))
    #expect(cryptoResponse(service, ["HMAC", "sha256", String(repeating: "0b", count: 20), relative, "--key-in=hex", "--data-in=file"]).contains("Result: c63f4ce3ddbd9cb9b70a5d9d85818cfe521316b2abb61881b51e602eb9a265f9\r\n"))
    #expect(cryptoResponse(["Digest", "sha256", relative, "--data-in=file"]).contains("ghost required"))
    #expect(cryptoResponse(["Digest", "sha256", file.path, "--data-in=file"]).contains("Result: 994e06a5"))
}

@Test func `file hashing keeps published algorithm vectors and rejects special files`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "abc")
    try Data("abc".utf8).write(to: file)
    let service = InternalSaoriService(ghostDirectory: root)
    let vectors = ["md5": "900150983cd24fb0d6963f7d28e17f72", "sha1": "a9993e364706816aba3e25717850c26c9cd0d89d",
                   "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                   "sha384": "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
                   "sha512": "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"]
    for (algorithm, expected) in vectors {
        #expect(cryptoResponse(service, ["Digest", algorithm, "abc", "--data-in=file"]).contains("Result: \(expected)\r\n"))
    }
    try Data().write(to: file)
    #expect(cryptoResponse(service, ["Digest", "sha256", "abc", "--data-in=file"]).contains("Result: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    let fifo = root.appending(path: "pipe")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    for path in ["missing", root.path, fifo.path, "https://example.com/file"] {
        #expect(cryptoResponse(service, ["Digest", "sha256", path, "--data-in=file"]).contains("file not found"))
    }
    #expect(cryptoResponse(service, ["HMAC", "sha256", "abc", "abc", "--key-in=file"]).contains("unsupported algorithm"))
}

@Test func `file hashing aborts on cancellation and truncation rather than returning a partial hash`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try Data(repeating: 1, count: 131_072).write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    var updates = 0
    #expect(throws: InternalSaoriService.Failure.self) {
        try InternalSaoriCrypto.Input.file(root).consume(isCancelled: { updates == 1 }) { _ in updates += 1 }
    }
    #expect(updates == 1)
    let writer = try FileHandle(forWritingTo: root)
    defer { try? writer.close() }
    #expect(throws: InternalSaoriService.Failure.self) {
        try InternalSaoriCrypto.Input.file(root).consume(isCancelled: { false }) { _ in try? writer.truncate(atOffset: 0) }
    }
}
