import Foundation
import Testing
import UtataneCore
@testable import UtataneModuleCatalog
import UtataneNetwork

@Test func `new ghost suggests missing SHIORI and SAORI from catalog DLL names`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let managed = root.appending(path: "managed")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try Data().write(to: master.appending(path: "minato.dll"))
    try Data().write(to: master.appending(path: "saori_cpuid.dll"))
    try Data().write(to: master.appending(path: "unrelated.dll"))
    let ghost = InstalledGhost(
        name: "Test", rootDirectory: root, defaultShellDirectory: root.appending(path: "shell/master"),
        shioriFilename: "minato.dll"
    )
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"minato","displayName":"minato","kinds":["shiori"],"windowsFilenames":["minato.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/minato.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"shiori","version":"1","revision":1}]},
      {"id":"saori-cpuid","displayName":"saori_cpuid","kinds":["saori"],"windowsFilenames":["saori_cpuid.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/saori.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"saori","version":"1","revision":1}]}
    ]}
    """.utf8))
    let scanner = GhostModuleRequirements()
    #expect(Set(scanner.unresolved(for: ghost, applicationSupportURL: managed).map(\.kind)) == ["SHIORI", "SAORI"])
    #expect(Set(scanner.missing(for: ghost, in: catalog, applicationSupportURL: managed).map(\.id))
        == ["minato", "saori-cpuid"])
    let limitedCatalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"minato","displayName":"minato","kinds":["shiori"],"windowsFilenames":["minato.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/minato.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"shiori","version":"1","revision":1}]}
    ]}
    """.utf8))
    #expect(scanner.missing(for: ghost, in: limitedCatalog, applicationSupportURL: managed).map(\.id) == ["minato"])
    let expandedCatalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"new-saori","displayName":"New SAORI","kinds":["saori"],"windowsFilenames":["unrelated.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/new.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"saori","version":"1","revision":1}]}
    ]}
    """.utf8))
    #expect(scanner.unresolved(for: ghost, applicationSupportURL: managed, catalog: expandedCatalog).count == 3)
    #expect(scanner.missing(for: ghost, in: expandedCatalog, applicationSupportURL: managed).map(\.id) == ["new-saori"])

    let installed = managed.appending(path: "NativeShiori/minato/lib")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    let architecture: String = {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }()
    let manifest = Data("""
    {"schemaVersion":1,"id":"minato","version":"1","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["\(architecture)"],"files":{"lib/libminato.dylib":"test"}}
    """.utf8)
    try manifest.write(to: installed.deletingLastPathComponent().appending(path: "module.json"))
    try Data().write(to: installed.appending(path: "libminato.dylib"))
    try Data().write(to: master.appending(path: "libsaori_cpuid.dylib"))
    #expect(scanner.missing(for: ghost, in: catalog, applicationSupportURL: managed).isEmpty)
}
