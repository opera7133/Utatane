import Foundation
import Testing
import UtataneCore
@testable import UtataneModuleCatalog
import UtataneNetwork

@Test(arguments: [(5, "yaya-6"), (6, "yaya-6"), (0, "yaya-6")])
func `YAYA defaults to six regardless of DLL FileVersion`(major: Int, expected: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try Data("dic, talk.dic\n".utf8).write(to: master.appending(path: "yaya.txt"))
    try yayaDLLVersionFixture(major).write(to: master.appending(path: "yaya.dll"))
    if major == 6 {
        try Data().write(to: master.appending(path: "libyaya.dylib"))
    }
    let ghost = InstalledGhost(
        name: "Test", rootDirectory: root, defaultShellDirectory: root.appending(path: "shell/master"),
        shioriFilename: "yaya.dll"
    )
    let scanner = GhostModuleRequirements()
    #expect(scanner.unresolved(for: ghost, applicationSupportURL: root.appending(path: "managed")).map(\.id) == [expected])
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"yaya-6","displayName":"YAYA 6","kinds":["shiori"],"windowsFilenames":["yaya.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/yaya-6.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"shiori","version":"6","revision":1}]},
      {"id":"yaya","displayName":"YAYA 5","kinds":["shiori"],"windowsFilenames":["yaya.dll"],"availability":"candidate","artifacts":[{"path":"artifacts/yaya.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64","x86_64"],"minimumOS":"14.0","abi":"shiori","version":"5","revision":1}]}
    ]}
    """.utf8))
    #expect(scanner.missing(for: ghost, in: catalog, applicationSupportURL: root.appending(path: "managed")).map(\.id)
        == [expected])
}

private func yayaDLLVersionFixture(_ major: Int) -> Data {
    var data = Data(repeating: 0, count: 0x400)
    func put16(_ offset: Int, _ value: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    func put32(_ offset: Int, _ value: Int) {
        put16(offset, value)
        put16(offset + 2, value >> 16)
    }
    put16(0, 0x5A4D)
    put32(0x3C, 0x80)
    put32(0x80, 0x0000_4550)
    put16(0x86, 1)
    put16(0x94, 224)
    put16(0x98, 0x10B)
    put32(0x108, 0x1000)
    put32(0x10C, 0x200)
    put32(0x180, 0x200)
    put32(0x184, 0x1000)
    put32(0x188, 0x200)
    put32(0x18C, 0x200)
    put16(0x20E, 1)
    put32(0x210, 16)
    put32(0x214, 0x8000_0018)
    put16(0x226, 1)
    put32(0x228, 1)
    put32(0x22C, 0x8000_0030)
    put16(0x23E, 1)
    put32(0x240, 1041)
    put32(0x244, 0x48)
    put32(0x248, 0x1060)
    put32(0x24C, 92)
    put16(0x260, 92)
    put16(0x262, 52)
    for (index, unit) in "VS_VERSION_INFO".utf16.enumerated() {
        put16(0x266 + index * 2, Int(unit))
    }
    put32(0x288, 0xFEEF_04BD)
    put32(0x28C, 0x0001_0000)
    put32(0x290, major << 16)
    return data
}

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
