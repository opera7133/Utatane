import Foundation
import Testing
import UtataneCore
import UtataneMisakaNative
import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

private final class ModuleSaoriRecorder: NativeSaoriCalling, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    var events: [String] {
        lock.withLock { calls }
    }

    func load(_ path: String) {
        lock.withLock { calls.append("load:\(path)") }
    }

    func unload(_ path: String) {
        lock.withLock { calls.append("unload:\(path)") }
    }

    func call(_ path: String, arguments: [String]) -> String {
        lock.withLock { calls.append("call:\(path):\(arguments.joined(separator: ","))") }
        return "ホストの応答"
    }
}

private struct ModuleMisakaFixture {
    let root: URL
    let master: URL
    let state: URL
    init(dictionary: String = "$_Variable\n{$count=0}\n\n$OnBoot\n{$count++}{$count}") throws {
        root = FileManager.default.temporaryDirectory.appending(path: "module 日本語 \(UUID())")
        master = root.appending(path: "ghost/master")
        state = root.appending(path: "state/variables.json")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try "dictionaries\n{\nmisaka.txt\n}\n".write(to: master.appending(path: "misaka.ini"), atomically: true, encoding: .shiftJIS)
        try dictionary.write(to: master.appending(path: "misaka.txt"), atomically: true, encoding: .shiftJIS)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct MisakaModuleSelectionTests {
    @Test func `missing installation keeps builtin and explicit failure is reported`() async throws {
        let fixture = try ModuleMisakaFixture()
        defer { fixture.remove() }
        let resolver = UtataneModuleResolver(applicationSupportURL: fixture.root, bundledResourcesURL: nil, environment: [:])
        let engine = try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                                       variableStoreURL: fixture.state, moduleResolver: resolver)
        #expect(try await engine.handle(event: .boot)?.rawValue == "1")
        await engine.shutdown()
        let invalid = UtataneModuleResolver(environment: ["UTATANE_MISAKA_MODULE": fixture.root.appending(path: "missing.dylib").path])
        #expect(throws: UtataneModuleError.self) {
            try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                              variableStoreURL: fixture.state, moduleResolver: invalid)
        }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"] != nil))
struct MisakaModuleIntegrationTests {
    private var library: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"]!)
    }

    @Test func `ghost events host services and shutdown`() async throws {
        let fixture = try ModuleMisakaFixture(dictionary: """
        $_Variable
        {$loadsaori("test.dll")}

        $OnBoot
        {$saori("test.dll","こんにちは")}

        $OnEcho
        {$appendheader("Reference1: next")}{$reference(0)}
        """)
        defer { fixture.remove() }
        let caller = ModuleSaoriRecorder()
        let resolver = UtataneModuleResolver(environment: ["UTATANE_MISAKA_MODULE": library.path])
        let engine = try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                                       variableStoreURL: fixture.state, saoriCaller: caller, moduleResolver: resolver)
        #expect(try await engine.handle(event: .boot)?.rawValue == "ホストの応答")
        let response = try await engine.response(for: .shiori(id: "OnEcho", references: [0: "日本語"]))
        #expect(response.script?.rawValue == "日本語")
        #expect(response.references[1] == "next")
        await engine.shutdown()
        #expect(caller.events == ["load:test.dll", "call:test.dll:こんにちは", "unload:test.dll"])
        #expect(FileManager.default.fileExists(atPath: fixture.state.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.master.appending(path: "misaka_vars.json").path))
    }

    @Test func `independent sessions and persistence`() throws {
        let fixture = try ModuleMisakaFixture()
        defer { fixture.remove() }
        let request = ShioriRequest(method: "GET", headers: ShioriHeaders([ShioriHeader(name: "ID", value: "OnBoot")]))
        let first = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                             variableStoreURL: fixture.state, saoriCaller: ModuleSaoriRecorder())
        let second = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                              variableStoreURL: fixture.state.appendingPathExtension("two"), saoriCaller: ModuleSaoriRecorder())
        #expect(try first.request(request).value == "1")
        #expect(try first.request(request).value == "2")
        #expect(try second.request(request).value == "1")
        try first.close()
        #expect(try second.request(request).value == "2")
        try second.close()
        let restored = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                                variableStoreURL: fixture.state, saoriCaller: ModuleSaoriRecorder())
        #expect(try restored.request(request).value == "3")
        try restored.close()
    }

    @Test func `failed save can retry and discard does not write`() throws {
        let fixture = try ModuleMisakaFixture()
        defer { fixture.remove() }
        let parent = fixture.state.deletingLastPathComponent()
        try Data().write(to: parent)
        let session = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                               variableStoreURL: fixture.state, saoriCaller: ModuleSaoriRecorder())
        #expect(throws: UtataneModuleError.self) { try session.close() }
        try FileManager.default.removeItem(at: parent)
        try session.close()
        #expect(FileManager.default.fileExists(atPath: fixture.state.path))
        let unsaved = fixture.root.appending(path: "unsaved.json")
        let other = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                             variableStoreURL: unsaved, saoriCaller: ModuleSaoriRecorder())
        try other.discard()
        #expect(!FileManager.default.fileExists(atPath: unsaved.path))
        #expect(throws: UtataneModuleError.closed) { try other.request(ShioriRequest(method: "GET")) }
    }

    @Test func `native registry runs through host ABI`() throws {
        let fixture = try ModuleMisakaFixture(dictionary: """
        $_Variable
        {$loadsaori("textcopy2.dll")}

        $OnBoot
        {$saori("textcopy2.dll","クリップボード経由")}
        """)
        defer { fixture.remove() }
        let capture = ModuleTextCapture()
        let caller = NativeSaoriRegistry(baseDirectoryURL: fixture.master, textCopyHandler: { capture.set($0) })
        let session = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: fixture.master,
                                               variableStoreURL: fixture.state, saoriCaller: caller)
        _ = try session.request(ShioriRequest(method: "GET", headers: ShioriHeaders([ShioriHeader(name: "ID", value: "OnBoot")])))
        #expect(capture.value == "クリップボード経由")
        try session.close()
    }

    @Test func `deinit discards after save failure and releases host resources`() throws {
        let fixture = try ModuleMisakaFixture(dictionary: "$_Variable\n{$loadsaori(\"test.dll\")}\n\n$OnBoot\nOK")
        defer { fixture.remove() }
        try Data().write(to: fixture.state.deletingLastPathComponent())
        let caller = ModuleSaoriRecorder()
        var session: UtataneModuleSession? = try UtataneModuleSession(
            moduleURL: library, masterDirectoryURL: fixture.master,
            variableStoreURL: fixture.state, saoriCaller: caller
        )
        #expect(session != nil)
        session = nil
        #expect(caller.events == ["load:test.dll", "unload:test.dll"])
        #expect(!FileManager.default.fileExists(atPath: fixture.state.path))
    }
}

private final class ModuleTextCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    var value: String {
        lock.withLock { text }
    }

    func set(_ value: String) {
        lock.withLock { text = value }
    }
}
