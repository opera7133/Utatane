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
