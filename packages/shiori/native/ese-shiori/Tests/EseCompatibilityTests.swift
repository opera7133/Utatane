import Foundation
import Testing
import UtataneCore
@testable import UtataneEseShioriNative
import UtataneShiori

@Test func `uses configured interval for internally scheduled random talk`() {
    var evaluator = EseEvaluator(
        dictionary: EseDictionary(rules: [
            EseRule(kind: .event, conditions: ["OnRandomTalk"], values: [#"\0scheduled\e"#])
        ]),
        talkInterval: 2
    )
    #expect(evaluator.response(for: request(id: "OnSecondChange", references: [3: "1"])).isEmpty)
    #expect(evaluator.response(for: request(id: "OnSecondChange", references: [3: "1"])) == #"\0scheduled\e"#)
    #expect(evaluator.talkSeconds == 0)
}

@Test func `getghost searches notified ghosts and reflect selects the response target`() {
    var evaluator = EseEvaluator(
        dictionary: EseDictionary(rules: [
            EseRule(
                kind: .event,
                conditions: ["OnProbe"],
                values: [#"$GETGHOST("Mayura",1,0)hello$REFLECT()"#]
            )
        ])
    )
    _ = evaluator.response(for: request(id: "otherghostname", references: [
        0: "Sakura\u{1}0\u{1}1", 1: "Mayura\u{1}2\u{1}3"
    ]))
    #expect(evaluator.response(for: request(id: "OnProbe")) == "hello")
    #expect(evaluator.storage[1] == "Mayura")
    #expect(evaluator.reflectedTarget == "Mayura")
}

@Test func `writefile stores stack content outside the ghost directory`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "utatane-ese-write-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master", directoryHint: .isDirectory)
    let state = root.appending(path: "state/state.json")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "[ESEAI]\nDIC_CHAR_SET=UTF-8\n".write(to: master.appending(path: "eseai.ini"), atomically: true, encoding: .utf8)
    try "##EVNT=(\"OnProbe\")\n$PUSH(\"hello\",1,0)$WRITEFILE(\"USER.DAT\",1,1)done\n".write(
        to: master.appending(path: "eseai_probe.txt"), atomically: true, encoding: .utf8
    )
    let engine = try NativeEseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    let response = try await engine.handle(event: .shiori(id: "OnProbe", references: [:]))
    #expect(response?.rawValue == "done")
    let written = root.appending(path: "state/ese-shiori-files/USER.DAT")
    #expect(try String(contentsOf: written, encoding: .utf8) == "hello\r\n")
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "USER.DAT").path))
}

@Test func `readnews advances through materia headline lines`() {
    var evaluator = EseEvaluator(
        dictionary: EseDictionary(rules: [
            EseRule(kind: .event, conditions: ["OnProbe"], values: [#"$READNEWS("NEWS.TXT",4,1)|$POP(4)"#])
        ]),
        fileContents: ["NEWS.TXT": "[SAKURA]\r\nfirst\r\nsecond\r\n"]
    )
    let first = evaluator.response(for: request(id: "OnProbe"))
    #expect(first == "first|first")
    #expect(evaluator.storage[4] == "first")
    #expect(evaluator.newsCounters["NEWS.TXT"] == 1)
    #expect(evaluator.response(for: request(id: "OnProbe")) == "second|second")
    #expect(evaluator.response(for: request(id: "OnProbe")) == "|")
}

@Test func `readnews counter survives an engine restart`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "utatane-ese-news-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master", directoryHint: .isDirectory)
    let state = root.appending(path: "state/state.json")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "[ESEAI]\nDIC_CHAR_SET=UTF-8\n".write(to: master.appending(path: "eseai.ini"), atomically: true, encoding: .utf8)
    try "[SAKURA]\r\nfirst\r\nsecond\r\n".write(to: master.appending(path: "NEWS.TXT"), atomically: true, encoding: .utf8)
    try "##EVNT=(\"OnProbe\")\n$READNEWS(\"NEWS.TXT\",4,1)\n".write(
        to: master.appending(path: "eseai_probe.txt"), atomically: true, encoding: .utf8
    )

    var engine = try NativeEseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    #expect(try await engine.handle(event: .shiori(id: "OnProbe", references: [:]))?.rawValue == "first")
    await engine.shutdown()
    engine = try NativeEseShioriPersonalityEngine(masterDirectoryURL: master, stateStoreURL: state)
    #expect(try await engine.handle(event: .shiori(id: "OnProbe", references: [:]))?.rawValue == "second")
}

@Test func `strlength follows the configured legacy byte encoding`() {
    var evaluator = EseEvaluator(
        dictionary: EseDictionary(rules: [EseRule(kind: .event, conditions: ["OnProbe"], values: [#"$STRLENGTH("abc한글")"#])]),
        dictionaryCharset: "EUC-KR"
    )
    #expect(evaluator.response(for: request(id: "OnProbe")) == "7")
}

private func request(id: String, references: [Int: String] = [:]) -> ShioriRequest {
    var headers = ShioriHeaders([ShioriHeader(name: "ID", value: id)])
    for (index, value) in references.sorted(by: { $0.key < $1.key }) {
        headers.append(name: "Reference\(index)", value: value)
    }
    return ShioriRequest(method: "GET", headers: headers)
}
