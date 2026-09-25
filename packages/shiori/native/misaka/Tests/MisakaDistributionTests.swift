import Foundation
import Testing
import UtataneCore
import UtataneGhostKit
import UtataneMisakaNative
import UtataneModuleHost
import UtataneNativeSaori
import UtatanePlugin
import UtataneShiori

private struct DistributionFixture {
    let root: URL
    let master: URL
    let state: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "配布確認 \(UUID())")
        master = root.appending(path: "ghost/master")
        state = root.appending(path: "state/variables.json")
        let shell = root.appending(path: "shell/master")
        for directory in [master, shell] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "name,Master\n".write(to: shell.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
        try "name,Sample\nshiori,renamed.dll\nshiori.macos,libmisaka.dylib\n".write(
            to: master.appending(path: "descript.txt"), atomically: true, encoding: .utf8
        )
        try "dictionaries\n{\nmisaka.txt\n}\n".write(to: master.appending(path: "misaka.ini"), atomically: true, encoding: .shiftJIS)
        try "$_Variable\n{$count=0}\n\n$OnBoot\n{$count++}{$count}\n\n$OnSaori\n{$saori(\"test.dll\",\"日本語\")}\n".write(
            to: master.appending(path: "misaka.txt"), atomically: true, encoding: .shiftJIS
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct DistributionSaori: NativeSaoriCalling {
    func load(_: String) {}
    func unload(_: String) {}
    func call(_: String, arguments: [String]) -> String {
        arguments.joined(separator: ",")
    }
}

private final class ReentrantDistributionSaori: NativeSaoriCalling, @unchecked Sendable {
    private let lock = NSLock()
    private weak var session: DynamicLibraryModuleSession?
    func attach(_ session: DynamicLibraryModuleSession) {
        lock.withLock { self.session = session }
    }

    func load(_: String) {}
    func unload(_: String) {}
    func call(_: String, arguments _: [String]) -> String {
        guard let session = lock.withLock({ session }) else { return "missing" }
        do {
            _ = try session.request("GET SHIORI/3.0\r\nID: OnBoot\r\n\r\n")
            return "unexpected"
        } catch { return "busy" }
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"] != nil))
struct MisakaDistributionTests {
    private var library: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"]!)
    }

    @Test func `rejects reentry from saori`() throws {
        let fixture = try DistributionFixture()
        defer { fixture.remove() }
        let caller = ReentrantDistributionSaori()
        let session = try DynamicLibraryModuleSession(directoryURL: fixture.master, moduleURL: library,
                                                      variableStoreURL: fixture.state, saoriCaller: caller)
        caller.attach(session)
        let response = try session.request("GET SHIORI/3.0\r\nID: OnSaori\r\n\r\n")
        #expect(try ShioriMessageParser.parseResponse(response).value == "busy")
        try session.close()
    }

    @Test func `shared and bundled library`() async throws {
        let fixture = try DistributionFixture()
        defer { fixture.remove() }
        let relative = "libmisaka.dylib"
        let installed = fixture.root.appending(path: "common/misaka-native/lib/" + relative)
        let bundled = fixture.master.appending(path: relative)
        for target in [installed, bundled] {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: library, to: target)
        }
        #expect(try Data(contentsOf: installed) == Data(contentsOf: bundled))
        let resolver = UtataneModuleResolver(applicationSupportURL: fixture.root.appending(path: "common"),
                                             bundledResourcesURL: nil, environment: [:])
        #expect(try resolver.misakaModuleURL(masterDirectoryURL: fixture.master) == bundled)
        let ghost = try GhostPackageLoader().loadGhost(at: fixture.root)
        #expect(ghost.shioriMacOSFilename == relative)
        // The same loader used by shiori.macos; no DLL or global installation is required.
        try FileManager.default.removeItem(at: installed)
        let direct = try DynamicLibraryModuleSession(directoryURL: fixture.master,
                                                     moduleURL: fixture.master.appending(path: #require(ghost.shioriMacOSFilename)),
                                                     variableStoreURL: fixture.state, saoriCaller: DistributionSaori())
        let wire = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        #expect(try ShioriMessageParser.parseResponse(direct.request(wire)).value == "1")
        let saoriWire = wire.replacingOccurrences(of: "OnBoot", with: "OnSaori")
        #expect(try ShioriMessageParser.parseResponse(direct.request(saoriWire)).value == "日本語")
        // A second ghost session in the same library must not share variables.
        let second = try DynamicLibraryModuleSession(directoryURL: fixture.master, moduleURL: bundled,
                                                     variableStoreURL: fixture.state.appendingPathExtension("second"))
        #expect(try ShioriMessageParser.parseResponse(second.request(wire)).value == "1")
        try second.close()
        try direct.close()
        #expect(throws: DynamicLibraryModuleError.self) { try direct.request(wire) }
        #expect(!FileManager.default.fileExists(atPath: fixture.master.appending(path: "misaka_vars.json").path))
        // Switch to a common installation using exactly the same bytes and saved state.
        try FileManager.default.moveItem(at: bundled, to: installed)
        #expect(try resolver.misakaModuleURL(masterDirectoryURL: fixture.master) == installed)
        let common = try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                                       variableStoreURL: fixture.state, moduleResolver: resolver)
        #expect(try await common.handle(event: .boot)?.rawValue == "2")
        await common.shutdown()
        // A distinct Swift image must be rejected before registering duplicate types.
        let changed = fixture.root.appending(path: "changed.dylib")
        var different = try Data(contentsOf: installed)
        different.append(0)
        try different.write(to: changed)
        #expect(throws: UtataneModuleError.self) { try UtataneModuleImage.open(changed) }
        // Recovery is optional and preserves the existing saved state.
        try Data("broken".utf8).write(to: bundled)
        #expect(throws: UtataneModuleError.self) {
            try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                              variableStoreURL: fixture.state, moduleResolver: UtataneModuleResolver(
                                                  applicationSupportURL: fixture.root.appending(path: "common"),
                                                  bundledResourcesURL: nil, environment: [:], allowsFallback: false
                                              ))
        }
        let recovered = try NativeMisakaPersonalityEngine(masterDirectoryURL: fixture.master,
                                                          variableStoreURL: fixture.state, moduleResolver: resolver)
        #expect(try await recovered.handle(event: .boot)?.rawValue == "3")
        await recovered.shutdown()
        let directRecovered = try DynamicLibraryModuleSession.open(directoryURL: fixture.master, moduleURL: bundled,
                                                                   variableStoreURL: fixture.state, moduleResolver: resolver)
        #expect(try ShioriMessageParser.parseResponse(directRecovered.request(wire)).value == "4")
        try directRecovered.close()
        try FileManager.default.removeItem(at: installed)
        #expect(throws: UtataneModuleError.self) {
            try DynamicLibraryModuleSession.open(directoryURL: fixture.master, moduleURL: bundled,
                                                 variableStoreURL: fixture.state, moduleResolver: resolver)
        }
    }
}
