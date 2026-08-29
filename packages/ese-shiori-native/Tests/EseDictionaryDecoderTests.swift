import Foundation
import Testing
import UtataneCore
import UtataneEseShioriNative

@Test func `decodes an obfuscated ese dictionary`() {
    let source = Data("#hello\r\nworld\r\n".utf8)
    var encoded = Data("ESESHIORI".utf8) + Data([0x42]) + Data(repeating: 0, count: 22)
    var key: UInt8 = 0x42
    for blockStart in stride(from: 0, to: source.count, by: 64) {
        for (index, byte) in source.dropFirst(blockStart).prefix(64).enumerated() {
            encoded.append(byte &+ (key &+ UInt8(truncatingIfNeeded: index * 5)))
        }
        key &+= 3
    }
    #expect(EseDictionaryDecoder.decode(encoded, charset: "UTF-8") == "#hello\r\nworld\r\n")
}

@Test func `loads the configured ese ghost without wine`() async throws {
    guard let path = ProcessInfo.processInfo.environment["UTATANE_ESE_SMOKE_PATH"] else { return }
    let engine = try NativeEseShioriPersonalityEngine(masterDirectoryURL: URL(filePath: path, directoryHint: .isDirectory))
    let boot = try await engine.handle(event: .boot)
    #expect(boot?.rawValue.isEmpty == false)
    #expect(boot?.rawValue.contains("$") == false)
    let talk = try await engine.handle(event: .randomTalk)
    #expect(talk?.rawValue.isEmpty == false)
    #expect(talk?.rawValue.contains("$") == false)
    let firstBoot = try await engine.handle(event: .shiori(id: "OnFirstBoot", references: [:]))
    #expect(firstBoot?.rawValue.contains("inputbox") == true)
    let menu = try await engine.handle(event: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: "Head",
        x: 0,
        y: 0
    )))
    #expect(menu?.rawValue.isEmpty == false)
}
