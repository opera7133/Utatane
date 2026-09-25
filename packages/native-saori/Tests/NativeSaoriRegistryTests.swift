import Foundation
import Testing
@testable import UtataneNativeSaori

@Test func `Wine choice uses the declared Windows SAORI`() {
    let module = RecordingExternalModule()
    let registry = NativeSaoriRegistry(
        baseDirectoryURL: URL(filePath: "/ghost/master"),
        prefersExternalWindowsDLL: true,
        externalModuleFactory: { url, _, _ in
            url.lastPathComponent == "saori_cpuid.dll" ? module : nil
        }
    )
    registry.load("saori_cpuid.dll")
    #expect(registry.call("saori_cpuid.dll", arguments: ["os.name"]) == "external")
}

@Test func `unknown module can use external factory within master directory`() {
    let module = RecordingExternalModule()
    let registry = NativeSaoriRegistry(
        baseDirectoryURL: URL(filePath: "/ghost/master"),
        externalModuleFactory: { url, _, _ in
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
        externalModuleFactory: { _, _, _ in
            recorder.wasCalled = true
            return RecordingExternalModule()
        }
    )

    registry.load("../outside.dll")
    #expect(!recorder.wasCalled)
}

@Test func `bundled SAORI aliases precede the managed library and receive ghost resources`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let saori = master.appending(path: "saori")
    let managed = root.appending(path: "managed")
    try FileManager.default.createDirectory(at: saori, withIntermediateDirectories: true)
    let plain = saori.appending(path: "kenonoke.dylib")
    let prefixed = saori.appending(path: "libkenonoke.dylib")
    let shared = managed.appending(path: "kenonoke/lib/libkenonoke.dylib")
    try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    for file in [plain, prefixed, shared] {
        try Data().write(to: file)
    }
    let recorder = CandidateRecorder()
    func registry() -> NativeSaoriRegistry {
        NativeSaoriRegistry(baseDirectoryURL: master, managedModulesURL: managed,
                            externalModuleFactory: { url, resourceURL, _ in
                                recorder.paths.append(url.path)
                                recorder.resources.append(resourceURL.path)
                                return RecordingExternalModule()
                            })
    }
    let first = registry()
    first.load("saori\\kenonoke.dll")
    #expect(recorder.paths == [plain.path])
    #expect(recorder.resources == [saori.path])
    try FileManager.default.removeItem(at: plain)
    let second = registry()
    second.load("saori/kenonoke.dll")
    #expect(recorder.paths.last == prefixed.path)
    try FileManager.default.removeItem(at: prefixed)
    let third = registry()
    third.load("saori/kenonoke.dll")
    #expect(recorder.paths.last == shared.path)
    #expect(recorder.resources.last == saori.path)
}

@Test func `broken bundled SAORI can use managed library`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master")
    let managed = root.appending(path: "managed")
    let local = master.appending(path: "textcopy2.dylib")
    let shared = managed.appending(path: "textcopy2/lib/libtextcopy2.dylib")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: local)
    try Data().write(to: shared)
    let recorder = CandidateRecorder()
    let registry = NativeSaoriRegistry(baseDirectoryURL: master, managedModulesURL: managed,
                                       externalModuleFactory: { url, _, _ in
                                           recorder.paths.append(url.path)
                                           return url == shared ? RecordingExternalModule() : nil
                                       })
    registry.load("textcopy2.dll")
    #expect(recorder.paths == [local.path, shared.path])
    #expect(registry.call("textcopy2.dll", arguments: ["hello"]) == "external")
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

private final class CandidateRecorder: @unchecked Sendable {
    var paths: [String] = []
    var resources: [String] = []
}
