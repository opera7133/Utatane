import Foundation
import Testing
@testable import UtataneContent

@Test
func `generates updates2.dau manifest with MD5 hashes`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let subDir = temp.appending(path: "ghost/master", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    try Data("test content 1".utf8).write(to: subDir.appending(path: "a.txt"))
    try Data("test content 2".utf8).write(to: temp.appending(path: "b.txt"))
    try Data("ignored".utf8).write(to: temp.appending(path: ".DS_Store"))
    try Data("ignored var".utf8).write(to: temp.appending(path: "saved_variable.cfg"))

    let generator = UpdateDataGenerator()
    let result = try generator.generate(in: temp)

    #expect(result.fileCount == 2)
    #expect(FileManager.default.fileExists(atPath: result.manifestURL.path))

    let content = try String(contentsOf: result.manifestURL, encoding: .utf8)
    let lines = content.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    #expect(lines.count == 2)
    #expect(lines[0].hasPrefix("b.txt\u{1}"))
    #expect(lines[0].contains("\u{1}size=14\u{1}"))
    #expect(lines[0].contains("\u{1}date="))
    #expect(lines[0].hasSuffix("\u{1}charset=UTF-8\u{1}"))
    #expect(lines[1].hasPrefix("ghost/master/a.txt\u{1}"))
    #expect(!lines[1].contains("charset="))
    #expect(content.contains("\r\n"))
}

@Test
func `developer options and standard exclusions filter update data`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    for directory in ["ghost/master/profile", "shell/old", "shell/master"] {
        try FileManager.default.createDirectory(
            at: temp.appending(path: directory, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }
    try Data("keep".utf8).write(to: temp.appending(path: "shell/master/surface0.png"))
    try Data("skip".utf8).write(to: temp.appending(path: "shell/old/surface1.png"))
    try Data("skip".utf8).write(to: temp.appending(path: "ghost/master/private.dat"))
    try Data("skip".utf8).write(to: temp.appending(path: "ghost/master/profile/state.txt"))
    try Data("skip".utf8).write(to: temp.appending(path: "Thumbs.db"))
    try "shell/old/,noupdate\nghost/master/*.dat,nonar,noupdate\n"
        .write(to: temp.appending(path: "developer_options.txt"), atomically: true, encoding: .utf8)

    let result = try UpdateDataGenerator().generate(in: temp)
    let content = try String(contentsOf: result.manifestURL, encoding: .utf8)

    #expect(result.fileCount == 2)
    #expect(content.contains("developer_options.txt\u{1}"))
    #expect(content.contains("shell/master/surface0.png\u{1}"))
    #expect(!content.contains("shell/old/"))
    #expect(!content.contains("private.dat"))
    #expect(!content.contains("profile/state.txt"))
    #expect(!content.contains("Thumbs.db"))
}

@Test
func `later developer option rule replaces earlier options`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    try "savedata.txt,nonar,noupdate\nsavedata.txt,nonar\n"
        .write(to: temp.appending(path: "developer_options.txt"), atomically: true, encoding: .utf8)

    let options = try DeveloperOptions.load(from: temp)
    #expect(!options.excludesFromUpdate(relativePath: "savedata.txt"))
}

@Test
func `update ignore include and negation filter generated files`() throws {
    let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: temp.appending(path: "ghost/master"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    for name in ["keep.txt", "skip.txt", "keep.dat"] {
        try Data(name.utf8).write(to: temp.appending(path: "ghost/master/\(name)"))
    }
    try "*.txt\n!keep.txt\n".write(to: temp.appending(path: ".sharedignore"), atomically: true, encoding: .utf8)
    try "include:.sharedignore\n".write(to: temp.appending(path: ".updateignore"), atomically: true, encoding: .utf8)
    try "ghost/**\n".write(to: temp.appending(path: ".updateinclude"), atomically: true, encoding: .utf8)

    let result = try UpdateDataGenerator().generate(in: temp)
    let content = try String(contentsOf: result.manifestURL, encoding: .utf8)
    #expect(content.contains("ghost/master/keep.txt\u{1}"))
    #expect(content.contains("ghost/master/keep.dat\u{1}"))
    #expect(!content.contains("ghost/master/skip.txt\u{1}"))
}
