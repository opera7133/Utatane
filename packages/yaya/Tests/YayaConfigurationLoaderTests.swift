import Foundation
import Testing
@testable import UtataneYaya

@Test func `resolves include and include EX using yaya directory rules`() throws {
    try withFixture { root in
        try write("\u{FEFF}" + """
        charset.dic, UTF-8
        include, system/config.txt
        includeEX, feature/config.txt
        dic, root.dic
        """, to: root.appendingPathComponent("yaya.txt"))
        try write("dic, from-system.dic", to: root.appendingPathComponent("system/config.txt"))
        try write("dic, from-feature.dic", to: root.appendingPathComponent("feature/config.txt"))
        try write("", to: root.appendingPathComponent("from-system.dic"))
        try write("", to: root.appendingPathComponent("feature/from-feature.dic"))
        try write("", to: root.appendingPathComponent("root.dic"))

        let configuration = try YayaConfigurationLoader().load(masterDirectory: root)

        #expect(configuration.includedConfigurationURLs.map(\.lastPathComponent) == ["yaya.txt", "config.txt", "config.txt"])
        #expect(configuration.dictionaries.map(\.url.path) == [
            root.appendingPathComponent("from-system.dic").path,
            root.appendingPathComponent("feature/from-feature.dic").path,
            root.appendingPathComponent("root.dic").path
        ])
        #expect(configuration.dictionaries.allSatisfy { $0.encoding == .utf8 })
        #expect(configuration.diagnostics.isEmpty)
    }
}

@Test func `supports optional dictionary and explicit encoding`() throws {
    try withFixture { root in
        try write("""
        charset.dic, UTF-8
        dicif, missing.dic
        dic, legacy.dic, Shift_JIS
        """, to: root.appendingPathComponent("yaya.txt"))
        try write("", to: root.appendingPathComponent("legacy.dic"))

        let configuration = try YayaConfigurationLoader().load(masterDirectory: root)

        #expect(configuration.dictionaries.count == 1)
        #expect(configuration.dictionaries[0].url.lastPathComponent == "legacy.dic")
        #expect(configuration.dictionaries[0].encoding == .shiftJIS)
        #expect(configuration.diagnostics.isEmpty)
    }
}

@Test func `reports missing required dictionary`() throws {
    try withFixture { root in
        try write("dic, missing.dic", to: root.appendingPathComponent("yaya.txt"))

        let configuration = try YayaConfigurationLoader().load(masterDirectory: root)

        #expect(configuration.dictionaries.count == 1)
        #expect(configuration.diagnostics.count == 1)
        #expect(configuration.diagnostics[0].severity == .error)
    }
}

@Test func `rejects configuration that escapes master directory`() throws {
    try withFixture { root in
        try write("include, ../outside.txt", to: root.appendingPathComponent("yaya.txt"))

        #expect(throws: YayaConfigurationError.pathEscapesRoot(root.deletingLastPathComponent().appendingPathComponent("outside.txt").path)) {
            try YayaConfigurationLoader().load(masterDirectory: root)
        }
    }
}

private func withFixture(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("UtataneYayaTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}
