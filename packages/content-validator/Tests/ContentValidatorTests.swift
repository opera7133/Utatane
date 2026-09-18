import Foundation
import Testing
@testable import UtataneContentValidator

@Test(arguments: ["libexample.dylib", "shiolink.dll"])
func `validates the macOS SHIORI choice instead of the Windows declaration`(filename: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let shell = root.appending(path: "shell/master")
    for directory in [master, shell] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("name,Shared\nshiori,yaya.dll\nshiori.macos,\(filename)\n".utf8)
        .write(to: master.appending(path: "descript.txt"))
    try Data().write(to: master.appending(path: "yaya.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    let report = ContentValidator().validate(ghostRoot: root)
    if filename == "shiolink.dll" {
        #expect(report.shiori == "SHIOLINK")
        #expect(report.shioriAssessment?.identifier == "shiolink")
        #expect(report.shioriAssessment?.supportStatus == .supported)
        #expect(report.shioriAssessment?.runtimeRequirement == .configuredExecutable)
        #expect(!report.diagnostics.contains { $0.code == "shiori.missing-module" })
    } else {
        #expect(report.shiori == "外部macOS SHIORI")
        #expect(report.shioriAssessment?.identifier == "external-posix-shiori")
        #expect(report.shioriAssessment?.supportStatus == .supported)
        #expect(report.shioriAssessment?.execution == .dynamicLibrary)
        #expect(report.diagnostics.contains {
            $0.code == "shiori.missing-module" && $0.message.contains(filename)
        })
        try Data().write(to: master.appending(path: filename))
        #expect(!ContentValidator().validate(ghostRoot: root).diagnostics.contains {
            $0.code == "shiori.missing-module"
        })
    }
}

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
    #expect(report.shioriAssessment?.identifier == "yaya")
    #expect(report.shioriAssessment?.supportStatus == .supported)
    #expect(report.shioriAssessment?.provisioning == .included)
    #expect(report.shioriAssessment?.runtimeRequirement?.rawValue == "none")
    #expect(report.diagnostics.contains { $0.code == "shell.missing-default-surface" })
    #expect(report.diagnostics.contains { $0.code == "shell.missing-element" })
    #expect(report.diagnostics.contains {
        $0.code == "sakurascript.unknown" && $0.line == 1 && $0.message.contains(#"\g"#)
    })
}

@Test
func `does not report parameterized SakuraScript assembled by dictionary code`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shell = root.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
    try Data("name,Fragments\nshiori,yaya.dll\n".utf8).write(to: master.appending(path: "descript.txt"))
    try Data(#"talk = "\0\p[" + scope + "]\q[" + label + ",id]""#.utf8)
        .write(to: master.appending(path: "talk.dic"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    try Data().write(to: shell.appending(path: "surface0.png"))

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(!report.diagnostics.contains { $0.code == "sakurascript.unknown" })
}

@Test
func `returns one load error for an invalid ghost root`() {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(report.errorCount == 1)
    #expect(report.shioriAssessment == nil)
    #expect(report.diagnostics.first?.code == "ghost.load")
}

@Test
func `reports unknown SHIORI support without losing its filename`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shell = root.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
    try Data("name,Unknown\nshiori,mystery.bin\n".utf8).write(to: master.appending(path: "descript.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    try Data().write(to: shell.appending(path: "surface0.png"))

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(report.shiori == "mystery.bin")
    #expect(report.shioriAssessment?.identifier == nil)
    #expect(report.shioriAssessment?.displayName == "mystery.bin")
    #expect(report.shioriAssessment?.supportStatus == .unknown)
}

@Test
func `reports a Windows DLL as compatibility layer support requiring Wine`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master", directoryHint: .isDirectory)
    let shell = root.appending(path: "shell/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
    try Data("name,Windows DLL\nshiori,custom.dll\n".utf8).write(to: master.appending(path: "descript.txt"))
    try Data("name,Master\n".utf8).write(to: shell.appending(path: "descript.txt"))
    try Data().write(to: shell.appending(path: "surface0.png"))

    let report = ContentValidator().validate(ghostRoot: root)

    #expect(report.shiori == "外部Windows SHIORI")
    #expect(report.shioriAssessment?.identifier == "external-windows-shiori")
    #expect(report.shioriAssessment?.supportStatus == .compatibilityLayer)
    #expect(report.shioriAssessment?.execution?.rawValue == "windowsDLL")
    #expect(report.shioriAssessment?.runtimeRequirement?.rawValue == "wine")
}
