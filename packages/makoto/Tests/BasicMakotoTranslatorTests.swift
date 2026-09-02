import Foundation
import Testing
@testable import UtataneMakoto

@Test
func `loads basic makoto lists and switches them with legacy speaker commands`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("[SAKURA]\nA,B,C\nX,Y\nONE\n".utf8)
        .write(to: directory.appending(path: "makoto0.lst"))
    try Data("[SAKURA]\nA,D,E\nX,Z\nONE,TWO\n".utf8)
        .write(to: directory.appending(path: "makoto1.lst"))

    let translator = try BasicMakotoTranslator(masterDirectoryURL: directory)
    #expect(translator.translate("\\hAAAA X ONE\\uAAAA X ONE\\hA") == "\\hB,CB,CB,CB,C Y ONE\\uD,ED,ED,ED,E Z TWO\\hB,C")
}

@Test
func `detects basic makoto separately from ParticleMakoto configuration`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appending(path: "makoto.dll"))
    try Data("[SAKURA]\nA,B\n".utf8).write(to: directory.appending(path: "makoto0.lst"))

    #expect(BasicMakotoTranslator.supports(masterDirectoryURL: directory))
    #expect(!ParticleMakotoTranslator.supports(masterDirectoryURL: directory))
}
