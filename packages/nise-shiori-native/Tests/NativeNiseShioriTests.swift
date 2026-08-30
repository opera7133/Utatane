import Foundation
import Testing
import UtataneCore
@testable import UtataneNiseShioriNative

@Test func `loads events words variables and persistent state`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let master = root.appending(path: "master", directoryHint: .isDirectory)
    let state = root.appending(path: "state/nise.json")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let description = try #require("sakura.name,偽さくら\nkero.name,偽うにゅう\n".data(using: .shiftJIS))
    try description.write(to: master.appending(path: "descript.txt"))
    let dictionary = """
    #Charset: UTF-8
    \\ms,ねこ
    \\ev,OnBoot & %hour>=0,\\0%sakuranameと%ms。\\set[count=1+2]\\e
    \\ev,OnMouseDoubleClick & %get[count]=3,\\0クリック\\e
    """
    try Data(dictionary.utf8).write(to: master.appending(path: "ai.txt"))

    var engine: NativeNiseShioriPersonalityEngine? = try .init(masterDirectoryURL: master, stateStoreURL: state)
    let boot = try await engine?.handle(event: .boot)?.rawValue
    #expect(boot == "\\0偽さくらとねこ。\\e")
    engine = nil
    let restored = try NativeNiseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let click = try await restored.handle(event: .mouse(.init(kind: .doubleClick, scope: 0, region: nil, x: 1, y: 2, button: 0)))?.rawValue
    #expect(click == "\\0クリック\\e")
}

@Test func `uses dtx dictionaries instead of txt when encrypted dictionary exists`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("\\e,plain".utf8).write(to: root.appending(path: "ai.txt"))
    let clear = Data("#Charset: UTF-8\n\\e,encrypted".utf8)
    try encrypt(clear).write(to: root.appending(path: "ai.dtx"))

    let dictionary = try NiseDictionary.load(from: root)
    #expect(dictionary.words["\\e"] == ["encrypted"])
}

@Test func `supports only niseshiori ghosts with dictionaries`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appending(path: "ai1.txt"))
    #expect(NativeNiseShioriPersonalityEngine.supports(masterDirectoryURL: root, shioriFilename: "NISESHIORI.DLL"))
    #expect(!NativeNiseShioriPersonalityEngine.supports(masterDirectoryURL: root, shioriFilename: "ese-shiori.dll"))
}

@Test func `loads the original 1 0 20 sample dictionaries when available`() async throws {
    let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let master = repository.appending(path: "References/Local/nss1_0_20/master", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    let state = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: state) }

    let dictionary = try NiseDictionary.load(from: master)
    #expect(!dictionary.events.isEmpty)
    let engine = try NativeNiseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let response = try await engine.handle(event: .boot)?.rawValue
    #expect(response?.isEmpty == false)
    let randomTalk = try await engine.handle(event: .randomTalk)?.rawValue
    #expect(randomTalk?.isEmpty == false)
}

private func encrypt(_ data: Data) -> Data {
    var key = 0x61
    var result: [UInt8] = []
    for byte in data {
        if byte == 0x0A {
            result.append(0x40); continue
        }
        let low = Int(byte & 0x03)
        let mid = Int((byte >> 2) & 0x03)
        let highMid = Int((byte >> 4) & 0x03)
        let high = Int((byte >> 6) & 0x03)
        let encodedSecond = low | (high << 2)
        let encodedFirst = mid | (highMid << 2)
        let firstKey = key
        key += 9
        let secondKey = key
        key += 2
        if key > 0xDD {
            key = 0x61
        }
        result.append(UInt8(truncatingIfNeeded: encodedFirst + secondKey))
        result.append(UInt8(truncatingIfNeeded: encodedSecond + firstKey))
    }
    return Data(result)
}
