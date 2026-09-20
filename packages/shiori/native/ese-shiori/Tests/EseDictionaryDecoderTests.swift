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
    #expect(boot?.rawValue.contains("%") == false)
    #expect(boot?.rawValue.contains(#"\1\s[10]"#) == true)
    let talk = try await engine.handle(event: .randomTalk)
    #expect(talk?.rawValue.isEmpty == false)
    #expect(talk?.rawValue.contains("$") == false)
    let firstBoot = try await engine.handle(event: .shiori(id: "OnFirstBoot", references: [:]))
    #expect(firstBoot?.rawValue.contains("inputbox") == true)
    let nameInput = try await engine.handle(event: .shiori(
        id: "OnUserInput",
        references: [0: "SetUsername", 1: "테스트"]
    ))
    #expect((nameInput?.rawValue.components(separatedBy: #"\q["#).count ?? 0) > 2)
    let nameChoice = try await engine.handle(event: .choice(id: "#emz41", arguments: []))
    #expect(nameChoice?.rawValue.contains("알았어") == true)
    #expect(nameChoice?.rawValue.contains("$") == false)
    let menu = try await engine.handle(event: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: "Head",
        x: 0,
        y: 0
    )))
    #expect(menu?.rawValue.isEmpty == false)
    #expect((menu?.rawValue.components(separatedBy: #"\q["#).count ?? 0) > 2)
    let menuChoice = try await engine.handle(event: .choice(id: "#emz01", arguments: []))
    #expect(menuChoice?.rawValue.contains(#"\q["#) == true)
}

@Test func `teaches and persists a word in the configured ese ghost`() async throws {
    guard let path = ProcessInfo.processInfo.environment["UTATANE_ESE_SMOKE_PATH"] else { return }
    let state = FileManager.default.temporaryDirectory
        .appending(path: "utatane-ese-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: state) }
    let master = URL(filePath: path, directoryHint: .isDirectory)
    let engine = try NativeEseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)

    let start = try await engine.handle(event: .shiori(id: "OnTeachEventStart", references: [0: "고양이"]))
    #expect(start?.rawValue.contains("inputbox,OnTeachEventInputed") == true)
    let learned = try await engine.handle(event: .shiori(id: "OnTeachEventInputed", references: [0: "사람"]))
    #expect(learned?.rawValue.contains("알았어") == true)
    _ = try await engine.handle(event: .close)

    let restored = try NativeEseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let known = try await restored.handle(event: .shiori(id: "OnTeachEventStart", references: [0: "고양이"]))
    #expect(known?.rawValue.contains("알고 있어") == true)
}
