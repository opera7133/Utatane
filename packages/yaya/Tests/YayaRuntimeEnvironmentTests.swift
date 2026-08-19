import Foundation
import Testing
@testable import UtataneYaya

@Test func `native runtime environment confines persistence and files to its root`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let dataURL = root.appendingPathComponent("data.txt")
    try Data("hello".utf8).write(to: dataURL)
    let environment = YayaNativeRuntimeEnvironment(
        rootDirectory: root,
        saveFileURL: root.appendingPathComponent("save/variables.json")
    )

    #expect(try environment.fileSize(path: "data.txt") == 5)
    try environment.saveVariables(["count": .integer(3)], path: nil)
    #expect(try environment.restoreVariables(path: nil) == ["count": .integer(3)])
    #expect(throws: YayaRuntimeEnvironmentError.pathEscapesRoot("/tmp/outside.txt")) {
        try environment.fileSize(path: "/tmp/outside.txt")
    }
}

@Test func `native runtime environment manages text streams by confined path`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let environment = YayaNativeRuntimeEnvironment(rootDirectory: root)

    #expect(try environment.openFile(path: "logs/test.txt", mode: "w") == 1)
    #expect(try environment.writeLine("first", path: "logs/test.txt"))
    #expect(try environment.writeLine("second", path: "logs/test.txt"))
    #expect(try environment.closeFile(path: "logs/test.txt") == 1)
    #expect(try environment.openFile(path: "logs/test.txt", mode: "r") == 1)
    #expect(try environment.readLine(path: "logs/test.txt") == "first")
    #expect(try environment.readLine(path: "logs/test.txt") == "second")
    #expect(try environment.readLine(path: "logs/test.txt") == nil)
    #expect(try environment.closeFile(path: "logs/test.txt") == 1)
}

@Test func `evaluator obtains settings clock functions and persistence through its environment`() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 19,
        hour: 12,
        minute: 34,
        second: 56
    )))
    let environment = YayaNativeRuntimeEnvironment(
        rootDirectory: root,
        saveFileURL: root.appendingPathComponent("variables.json"),
        settings: ["custom": .string("before")],
        calendar: calendar,
        dateProvider: { date },
        uptimeProvider: { 12.5 }
    )
    let program = try YayaDictionaryParser.parse(source: """
    OnAlpha { 'a' }
    OnBeta { 'b' }
    Setting { SETSETTING('custom', 'after'); return GETSETTING('custom') }
    Clock { return GETTIME[0] + ':' + GETTIME[1] + ':' + GETTICKCOUNT }
    Functions { return GETFUNCLIST('On') }
    Persist { saved = 7; SAVEVAR; ERASEVAR('saved'); RESTOREVAR; return saved }
    Width { return ZEN2HAN('ＡＢＣ１２３！') + '|' + HAN2ZEN('12!', 'number,symbol') }
    Path { return SPLITPATH('system/test.dic') }
    File { FOPEN('talk.txt', 'w'); FWRITE('talk.txt', 'hello'); FCLOSE('talk.txt'); FOPEN('talk.txt', 'r'); _line = FREAD('talk.txt'); FCLOSE('talk.txt'); return _line }
    """)
    var evaluator = YayaEvaluator(program: program, environment: environment)

    #expect(try evaluator.call("Setting") == .string("after"))
    #expect(try evaluator.call("Clock") == .string("2026:8:12500"))
    #expect(try evaluator.call("Functions") == .array([.string("OnAlpha"), .string("OnBeta")]))
    #expect(try evaluator.call("Persist") == .integer(7))
    #expect(try evaluator.call("Width") == .string("ABC123!|１２！"))
    #expect(try evaluator.call("Path") == .array([
        .string(""), .string("system/"), .string("test"), .string("dic")
    ]))
    #expect(try evaluator.call("File") == .string("hello"))
}
