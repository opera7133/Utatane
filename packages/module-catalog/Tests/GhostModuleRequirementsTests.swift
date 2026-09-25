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
    let ghost = InstalledGhost(
        name: "Test", rootDirectory: root, defaultShellDirectory: root.appending(path: "shell/master"),
        shioriFilename: "minato.dll"
    )
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"minato","displayName":"minato","kinds":["shiori"],"windowsFilenames":["minato.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/minato.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"1","revision":1}]},
      {"id":"saori-cpuid","displayName":"saori_cpuid","kinds":["saori"],"windowsFilenames":["saori_cpuid.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/saori.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"saori","version":"1","revision":1}]}
    ]}
    """.utf8))
    let scanner = GhostModuleRequirements()
    #expect(Set(scanner.missing(for: ghost, in: catalog, applicationSupportURL: managed).map(\.id))
        == ["minato", "saori-cpuid"])

    let installed = managed.appending(path: "NativeShiori/minato/lib")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data().write(to: installed.deletingLastPathComponent().appending(path: "module.json"))
    try Data().write(to: installed.appending(path: "libminato.dylib"))
    try Data().write(to: master.appending(path: "libsaori_cpuid.dylib"))
    #expect(scanner.missing(for: ghost, in: catalog, applicationSupportURL: managed).isEmpty)
}
