import Foundation
import Testing
@testable import UtataneNativeSaori

@Test func `wmove exposes positions desktop size and horizontal movement`() {
    let windows = RecordingWindowController()
    let registry = NativeSaoriRegistry(baseDirectoryURL: URL(filePath: "/ghost/master"), windowController: windows)
    registry.load("modules\\wmove.dll")
    #expect(registry.call("wmove.dll", arguments: ["GET_POSITION", "1"]) == "100\u{1}125\u{1}150")
    #expect(registry.call("wmove.dll", arguments: ["GET_DESKTOP_SIZE"]) == "1440\u{1}900")
    #expect(registry.call("wmove.dll", arguments: ["MOVETO", "1", "20", "5"]) == "")
    #expect(windows.moves == [.init(scope: 1, x: 20, speed: 5)])
}

@Test func `system info reports macOS and processor count`() {
    let registry = NativeSaoriRegistry(baseDirectoryURL: URL(filePath: "/ghost/master"))
    registry.load("saori/saori_cpuid.dll")
    #expect(registry.call("saori_cpuid.dll", arguments: ["os.name"]) == "macOS")
    #expect(Int(registry.call("saori_cpuid.dll", arguments: ["cpu.num"])) ?? 0 > 0)
}

@Test func `keyword module loads Shift JIS classifications beside its module`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let moduleDirectory = root.appending(path: "saori", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)
    let source = "飲み物＝日本酒、酒\r\n場所＝酒場\r\n"
    let data = try #require(source.data(using: .shiftJIS))
    try data.write(to: moduleDirectory.appending(path: "keyword.txt"))

    let registry = NativeSaoriRegistry(baseDirectoryURL: root)
    registry.load("saori/kenonoke.dll")
    #expect(registry.call("kenonoke.dll", arguments: ["GETKEYWORD", "酒場で日本酒を飲む"])
        == "場所\u{1}飲み物")
}

@Test func `unknown module can use external factory within master directory`() {
    let module = RecordingExternalModule()
    let registry = NativeSaoriRegistry(
        baseDirectoryURL: URL(filePath: "/ghost/master"),
        externalModuleFactory: { url in
            url.path == "/ghost/master/saori/custom.dylib" ? module : nil
        }
    )

    registry.load("saori\\custom.dylib")
    #expect(registry.call("custom.dylib", arguments: ["one", "two"]) == "external")
    #expect(module.arguments == [["one", "two"]])
    registry.unload("custom.dylib")
    #expect(registry.call("custom.dylib", arguments: []) == "")
}

@Test func `external factory rejects relative paths outside master directory`() {
    let recorder = FactoryCallRecorder()
    let registry = NativeSaoriRegistry(
        baseDirectoryURL: URL(filePath: "/ghost/master"),
        externalModuleFactory: { _ in
            recorder.wasCalled = true
            return RecordingExternalModule()
        }
    )

    registry.load("../outside.dll")
    #expect(!recorder.wasCalled)
}

private final class RecordingWindowController: NativeSaoriWindowControlling, @unchecked Sendable {
    struct Move: Equatable { var scope: Int; var x: Int; var speed: Int }
    var moves: [Move] = []
    func frame(scope: Int) -> NativeSaoriWindowFrame? {
        scope == 1 ? .init(x: 100, y: 200, width: 50, height: 80) : nil
    }

    func desktopSize() -> (width: Int, height: Int) {
        (1440, 900)
    }

    func move(scope: Int, x: Int, speed: Int) {
        moves.append(.init(scope: scope, x: x, speed: speed))
    }
}

private final class RecordingExternalModule: ExternalSaoriModule, @unchecked Sendable {
    var arguments: [[String]] = []

    func call(arguments: [String]) -> String {
        self.arguments.append(arguments)
        return "external"
    }
}

private final class FactoryCallRecorder: @unchecked Sendable {
    var wasCalled = false
}
