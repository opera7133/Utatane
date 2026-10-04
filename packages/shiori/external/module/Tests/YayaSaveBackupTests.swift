import Foundation
import Testing
@testable import UtataneModuleHost

@Test func `YAYA backup preserves variables once and ignores dictionaries`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let save = root.appending(path: "yaya_variable.cfg")
    try Data("old variables".utf8).write(to: save)
    try Data("dictionary".utf8).write(to: root.appending(path: "talk.dic"))
    try YayaSaveBackup.prepare(in: root)
    try Data("new variables".utf8).write(to: save)
    try YayaSaveBackup.prepare(in: root)
    #expect(try String(contentsOf: root.appending(path: "Utatane-YAYA-backup/yaya_variable.cfg"), encoding: .utf8) == "old variables")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Utatane-YAYA-backup/talk.dic").path))
    #expect(try String(contentsOf: save, encoding: .utf8) == "new variables")
}

@Test func `YAYA backup rejects a linked save without leaving a partial backup`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("variables".utf8).write(to: root.appending(path: "real.cfg"))
    try FileManager.default.createSymbolicLink(atPath: root.appending(path: "yaya_variable.cfg").path, withDestinationPath: "real.cfg")
    #expect(throws: CocoaError.self) { try YayaSaveBackup.prepare(in: root) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["real.cfg", "yaya_variable.cfg"])
}
