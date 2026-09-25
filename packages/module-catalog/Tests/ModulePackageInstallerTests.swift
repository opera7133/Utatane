import CryptoKit
import Foundation
import Testing
@testable import UtataneModuleCatalog
import UtataneNetwork
import ZIPFoundation

@Test func `package installer verifies inventory and preserves existing module on failure`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "catalog-install-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = Data("library bytes".utf8)
    let libraryHash = digest(library)
    let manifest = Data("""
    {"schemaVersion":1,"id":"wmove","version":"1.0.0","revision":1,"abi":"saori-1","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libwmove.dylib":"\(libraryHash)"}}
    """.utf8)
    let valid = try makePackage(at: root.appending(path: "valid.zip"), entries: [
        ("wmove/lib/libwmove.dylib", library),
        ("wmove/module.json", manifest)
    ])
    let (module, artifact) = try catalogEntry(for: valid)
    let managed = root.appending(path: "managed")
    let destination = try ModulePackageInstaller().install(
        archiveURL: valid, module: module, artifact: artifact, managedRootURL: managed
    )
    #expect(try Data(contentsOf: destination.appending(path: "lib/libwmove.dylib")) == library)

    let unsafe = try makePackage(at: root.appending(path: "unsafe.zip"), entries: [
        ("wmove/../outside", Data("bad".utf8)),
        ("wmove/lib/libwmove.dylib", library),
        ("wmove/module.json", manifest)
    ])
    let (unsafeModule, unsafeArtifact) = try catalogEntry(for: unsafe)
    #expect(throws: ModulePackageInstallError.unsafeEntry) {
        try ModulePackageInstaller().install(
            archiveURL: unsafe, module: unsafeModule, artifact: unsafeArtifact, managedRootURL: managed
        )
    }
    #expect(try Data(contentsOf: destination.appending(path: "lib/libwmove.dylib")) == library)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "outside").path))

    let wrongManifest = Data("""
    {"schemaVersion":1,"id":"wmove","version":"1.0.0","revision":1,"abi":"saori-1","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libwmove.dylib":"\(String(repeating: "0", count: 64))"}}
    """.utf8)
    let badHash = try makePackage(at: root.appending(path: "bad-hash.zip"), entries: [
        ("wmove/lib/libwmove.dylib", library),
        ("wmove/module.json", wrongManifest)
    ])
    let (badModule, badArtifact) = try catalogEntry(for: badHash)
    #expect(throws: ModulePackageInstallError.manifestMismatch) {
        try ModulePackageInstaller().install(
            archiveURL: badHash, module: badModule, artifact: badArtifact, managedRootURL: managed
        )
    }
    #expect(try Data(contentsOf: destination.appending(path: "lib/libwmove.dylib")) == library)
}

private func makePackage(at url: URL, entries: [(String, Data)]) throws -> URL {
    let archive = try Archive(url: url, accessMode: .create)
    for (path, data) in entries {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return start < end ? data.subdata(in: start ..< end) : Data()
        }
    }
    return url
}

private func catalogEntry(for archive: URL) throws -> (SignedModuleCatalog.Module, SignedModuleCatalog.Module.Artifact) {
    let data = try Data(contentsOf: archive)
    let index = Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[{"id":"wmove","displayName":"wmove","kinds":["saori"],"availability":"candidate","artifacts":[{"path":"artifacts/wmove.zip","sha256":"\(digest(data))","size":\(data.count),"architectures":["arm64"],"minimumOS":"14.0","abi":"saori-1","version":"1.0.0","revision":1}]}]}
    """.utf8)
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: index)
    let module = try #require(catalog.modules.first)
    return try (module, #require(module.artifacts.first))
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MODULE_CATALOG_SNAPSHOT"] != nil))
func `package installer accepts complete local catalog snapshot`() throws {
    let snapshotPath = try #require(ProcessInfo.processInfo.environment["UTATANE_MODULE_CATALOG_SNAPSHOT"])
    let snapshot = URL(filePath: snapshotPath)
    let index = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data(contentsOf: snapshot.appending(path: "index.json")))
    let root = FileManager.default.temporaryDirectory.appending(path: "catalog-snapshot-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    var installed = 0
    for module in index.modules {
        for artifact in module.artifacts {
            let managed = root.appending(path: module.kinds == ["saori"] ? "NativeSaori" : "NativeShiori")
            let destination = try ModulePackageInstaller().install(
                archiveURL: snapshot.appending(path: artifact.path),
                module: module,
                artifact: artifact,
                managedRootURL: managed
            )
            #expect(FileManager.default.fileExists(atPath: destination.appending(path: "module.json").path))
            installed += 1
        }
    }
    #expect(installed > 0)
    #expect(installed == index.modules.reduce(0) { $0 + $1.artifacts.count })
}
