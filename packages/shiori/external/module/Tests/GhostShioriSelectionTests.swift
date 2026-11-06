import Foundation
import Testing
@testable import UtataneModuleHost

@Test @MainActor func `ghost SHIORI selections persist separately and clear to automatic without changing descriptors`() throws {
    let name = "SHIORI-selection-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let descriptor = root.appending(path: "descript.txt")
    try Data("shiori,yaya.dll\n".utf8).write(to: descriptor)
    let module = root.appending(path: "renamed.dylib")
    try Data().write(to: module)
    let a = root.appending(path: "a"), b = root.appending(path: "b")
    let selection = GhostShioriSelection(modulePath: module.path, kindID: "yaya-6")
    try GhostShioriSelectionStore(defaults: defaults).set(selection, for: a)
    let reloaded = try GhostShioriSelectionStore(defaults: #require(UserDefaults(suiteName: name)))
    #expect(try reloaded.selection(for: a) == selection)
    #expect(try reloaded.selection(for: b) == nil)
    #expect(try reloaded.selection(for: a.appending(path: "../a")) == selection)
    #expect(selection.kind == .yaya6)
    #expect(GhostShioriSelection(modulePath: "/libyaya.dylib").kind == .yaya)
    #expect(throws: (any Error).self) {
        try reloaded.set(GhostShioriSelection(modulePath: "/missing.dylib"), for: a)
    }
    #expect(try reloaded.selection(for: a) == selection)
    try reloaded.set(nil, for: a)
    #expect(try reloaded.selection(for: a) == nil)
    #expect(try String(contentsOf: descriptor, encoding: .utf8) == "shiori,yaya.dll\n")
}

@Test func `selected SHIORI validates paths kinds and disappearing files`() throws {
    for selection in [GhostShioriSelection(modulePath: "relative.dylib"),
                      GhostShioriSelection(modulePath: "/missing.dylib"),
                      GhostShioriSelection(modulePath: "/tmp/x.dll"),
                      GhostShioriSelection(modulePath: "/tmp/x.dylib", kindID: "unknown")]
    {
        #expect(throws: (any Error).self) { try selection.validatedModuleURL() }
    }
    let module = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).dylib")
    try Data().write(to: module)
    let selection = GhostShioriSelection(modulePath: module.path, kindID: "yaya-6")
    #expect(try selection.validatedModuleURL() == module)
    try FileManager.default.removeItem(at: module)
    #expect(throws: (any Error).self) { try selection.validatedModuleURL() }
}

@Test @MainActor func `corrupt selected SHIORI preference reports an error and can be cleared`() throws {
    let name = "SHIORI-corrupt-\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let ghost = URL(fileURLWithPath: "/tmp/test-ghost")
    let key = "utatane.ghost.shioriSelection." + Data(ghost.standardizedFileURL.path.utf8).base64EncodedString()
    defaults.set(Data("bad JSON".utf8), forKey: key)
    let store = GhostShioriSelectionStore(defaults: defaults)
    #expect(throws: (any Error).self) { try store.selection(for: ghost) }
    try store.set(nil, for: ghost)
    #expect(try store.selection(for: ghost) == nil)
}
