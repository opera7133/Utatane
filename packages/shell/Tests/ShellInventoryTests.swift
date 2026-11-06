import Foundation
import Testing
@testable import UtataneShell

private func inventoryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func `shell load derives image IDs and definitions from one directory inventory`() throws {
    let root = try inventoryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appending(path: "surface0.png")
    try Data().write(to: image)
    try Data().write(to: root.appending(path: "surface99.png"))
    var calls = 0
    let shell = try ShellLoader().load(from: root, contentsOfDirectory: { directory in
        #expect(directory == root)
        calls += 1
        // Model the directory snapshot before another image appeared on disk.
        return [image]
    })
    #expect(calls == 1)
    #expect(shell.surfaces.keys.sorted() == [0])
}

@Test func `reusing a shell loader rereads added deleted and edited files`() throws {
    let root = try inventoryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let loader = ShellLoader()
    let image0 = root.appending(path: "surface0.png"), image1 = root.appending(path: "surface1.gif")
    try Data().write(to: image0)
    #expect(try loader.load(from: root).surfaces.keys.sorted() == [0])
    try FileManager.default.removeItem(at: image0)
    try Data().write(to: image1)
    #expect(try loader.load(from: root).surfaces.keys.sorted() == [1])
    let definitions = root.appending(path: "surfaces.txt")
    try "surface1 {\nname,first\n}".write(to: definitions, atomically: true, encoding: .utf8)
    #expect(try loader.load(from: root).surfaces[1]?.name == "first")
    try "surface1 {\nname,second\n}".write(to: definitions, atomically: true, encoding: .utf8)
    #expect(try loader.load(from: root).surfaces[1]?.name == "second")
    try FileManager.default.removeItem(at: image1)
    #expect(throws: ShellError.missingSurface(id: 1, directory: root)) { try loader.loadSurface(id: 1, from: root) }
    try FileManager.default.removeItem(at: definitions)
    #expect(throws: ShellError.missingFile(root.appending(path: "surfaces.txt", directoryHint: .notDirectory))) { try loader.load(from: root) }
}

@Test func `shell inventory keeps hidden images but skips hidden definitions and legacy text`() throws {
    let root = try inventoryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let image = root.appending(path: "surface3.png")
    let hiddenDefinition = root.appending(path: "surfaces10.txt")
    let hiddenLegacy = root.appending(path: "surface9s.txt")
    try Data().write(to: image)
    try "surface3 {\nname,hidden\n}".write(to: hiddenDefinition, atomically: true, encoding: .utf8)
    try "collision0,0,0,10,10,Hidden".write(to: hiddenLegacy, atomically: true, encoding: .utf8)
    for var url in [image, hiddenDefinition, hiddenLegacy] {
        var values = URLResourceValues()
        values.isHidden = true
        try url.setResourceValues(values)
        #expect(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden == true)
    }
    let shell = try ShellLoader().load(from: root)
    #expect(shell.surfaces.keys.sorted() == [3])
    #expect(shell.surfaces[3]?.name == nil)
}

@Test func `directory listing failure propagates without partial shell results`() throws {
    let root = try inventoryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    var calls = 0
    #expect(throws: CocoaError(.fileReadNoPermission)) {
        try ShellLoader().load(from: root, contentsOfDirectory: { _ in
            calls += 1
            throw CocoaError(.fileReadNoPermission)
        })
    }
    #expect(calls == 1)
}
