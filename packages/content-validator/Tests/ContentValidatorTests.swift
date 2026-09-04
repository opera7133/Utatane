import Foundation
import Testing
@testable import UtataneContentValidator

@Test
func `reports missing surfaces elements and unknown SakuraScript`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shell = root.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
    try Data("name,Test\nshiori,yaya.dll\nsakura.seriko.defaultsurface,0\nkero.seriko.defaultsurface,10\n".utf8)
        .write(to: master.appending(path: "descript.txt"))
    try Data("dic,\\0known\\g[missing]\\e\n".utf8).write(to: master.appending(path: "talk.dic"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    try Data("surface0\n{\nelement0,overlay,missing.png,0,0\n}\n".utf8)
        .write(to: shell.appending(path: "surfaces.txt"))
    try Data().write(to: shell.appending(path: "surface0.png"))

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(report.ghostName == "Test")
    #expect(report.shiori == "YAYA")
    #expect(report.diagnostics.contains { $0.code == "shell.missing-default-surface" })
    #expect(report.diagnostics.contains { $0.code == "shell.missing-element" })
    #expect(report.diagnostics.contains {
        $0.code == "sakurascript.unknown" && $0.line == 1 && $0.message.contains(#"\g"#)
    })
}

@Test
func `returns one load error for an invalid ghost root`() {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "ghost.load")
}
