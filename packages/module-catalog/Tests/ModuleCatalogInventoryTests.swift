import Foundation
import Testing
@testable import UtataneModuleCatalog
import UtataneNetwork

@Test func `catalog inventory selects this Mac artifact and checks installed manifest`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"yaya","displayName":"YAYA","kinds":["shiori"],"availability":"candidate","artifacts":[
        {"path":"artifacts/arm.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"2.0.0","revision":1},
        {"path":"artifacts/intel.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["x86_64"],"minimumOS":"14.0","abi":"shiori","version":"1.0.0","revision":2}
      ]}
    ]}
    """.utf8))
    let module = try #require(catalog.modules.first)
    let arm = ModuleCatalogInventory(
        applicationSupportURL: root, architecture: "arm64",
        macOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    let intel = ModuleCatalogInventory(
        applicationSupportURL: root, architecture: "x86_64",
        macOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    #expect(arm.artifact(for: module)?.index == 0)
    #expect(intel.artifact(for: module)?.index == 1)
    #expect(arm.state(for: module) == .notInstalled)
    #expect(!arm.hasRequiredInitialModules)
    let directory = root.appending(path: "NativeShiori/yaya")
    try FileManager.default.createDirectory(at: directory.appending(path: "lib"), withIntermediateDirectories: true)
    try Data("module".utf8).write(to: directory.appending(path: "lib/libyaya.dylib"))
    func writeManifest(version: String, id: String = "yaya") throws {
        try Data("""
        {"schemaVersion":1,"id":"\(id)","version":"\(version)","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libyaya.dylib":"test"}}
        """.utf8).write(to: directory.appending(path: "module.json"))
    }
    try writeManifest(version: "1.0.0")
    #expect(arm.state(for: module) == .updateAvailable)
    #expect(intel.state(for: module) == .notInstalled)
    try writeManifest(version: "2.0.0")
    #expect(arm.state(for: module) == .current)
    #expect(arm.isInstalled(moduleID: "yaya", kind: "shiori"))
    #expect(!arm.hasRequiredInitialModules)
    let satori = root.appending(path: "NativeShiori/satori")
    try FileManager.default.createDirectory(at: satori.appending(path: "lib"), withIntermediateDirectories: true)
    try Data("module".utf8).write(to: satori.appending(path: "lib/libsatori.dylib"))
    try Data("""
    {"schemaVersion":1,"id":"satori","version":"1.0.0","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libsatori.dylib":"test"}}
    """.utf8).write(to: satori.appending(path: "module.json"))
    #expect(arm.hasRequiredInitialModules)
    #expect(!intel.hasRequiredInitialModules)
    try writeManifest(version: "3.0.0")
    #expect(arm.state(for: module) == .current)
    try writeManifest(version: "2.0.0", id: "other")
    #expect(arm.state(for: module) == .notInstalled)
}

@Test func `YAYA Tc versions sort and match the previous numeric label`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"yaya-6","displayName":"YAYA 6","kinds":["shiori"],"availability":"candidate","artifacts":[
        {"path":"artifacts/old.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"Tc603-2","revision":1},
        {"path":"artifacts/new.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"Tc603-3","revision":1}
      ]}
    ]}
    """.utf8))
    let module = try #require(catalog.modules.first)
    let inventory = ModuleCatalogInventory(
        applicationSupportURL: root, architecture: "arm64",
        macOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    #expect(inventory.artifact(for: module)?.index == 1)
    let directory = root.appending(path: "NativeShiori/yaya-6")
    try FileManager.default.createDirectory(at: directory.appending(path: "lib"), withIntermediateDirectories: true)
    try Data().write(to: directory.appending(path: "lib/libyaya-6.dylib"))
    try Data("""
    {"schemaVersion":1,"id":"yaya-6","version":"6.3.2","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libyaya-6.dylib":"test"}}
    """.utf8).write(to: directory.appending(path: "module.json"))
    #expect(inventory.state(for: module) == .updateAvailable)
    let matchingCatalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"yaya-6","displayName":"YAYA 6","kinds":["shiori"],"availability":"candidate","artifacts":[
        {"path":"artifacts/old.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"Tc603-2","revision":1}
      ]}
    ]}
    """.utf8))
    #expect(inventory.state(for: try #require(matchingCatalog.modules.first)) == .current)
}
