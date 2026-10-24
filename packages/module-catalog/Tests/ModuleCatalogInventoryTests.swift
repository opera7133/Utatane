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
    #expect(!arm.hasRequiredInitialModules)
    let six = root.appending(path: "NativeShiori/yaya-6")
    try FileManager.default.createDirectory(at: six.appending(path: "lib"), withIntermediateDirectories: true)
    try Data().write(to: six.appending(path: "lib/libyaya-6.dylib"))
    try Data("""
    {"schemaVersion":1,"id":"yaya-6","version":"Tc603-2","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/libyaya-6.dylib":"test"}}
    """.utf8).write(to: six.appending(path: "module.json"))
    #expect(arm.hasRequiredInitialModules)
    #expect(!intel.hasRequiredInitialModules)
    try writeManifest(version: "3.0.0")
    #expect(arm.state(for: module) == .current)
    try writeManifest(version: "2.0.0", id: "other")
    #expect(arm.state(for: module) == .notInstalled)
}

@Test(arguments: [("yaya-6", "Tc", "6.3.2", "603"), ("satori", "Mc", "2.3.2", "203")])
func `upstream versions sort and match previous numeric labels`(id: String, prefix: String, previous: String, code: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"\(id)","displayName":"YAYA 6","kinds":["shiori"],"availability":"candidate","artifacts":[
        {"path":"artifacts/old.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"\(prefix)\(code)-2","revision":1},
        {"path":"artifacts/new.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"\(prefix)\(code)-3","revision":1}
      ]}
    ]}
    """.utf8))
    let module = try #require(catalog.modules.first)
    let inventory = ModuleCatalogInventory(
        applicationSupportURL: root, architecture: "arm64",
        macOSVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
    )
    #expect(inventory.artifact(for: module)?.index == 1)
    let directory = root.appending(path: "NativeShiori/\(id)")
    try FileManager.default.createDirectory(at: directory.appending(path: "lib"), withIntermediateDirectories: true)
    try Data().write(to: directory.appending(path: "lib/lib\(id).dylib"))
    try Data("""
    {"schemaVersion":1,"id":"\(id)","version":"\(previous)","revision":1,"abi":"shiori","minimumOS":"14.0","architectures":["arm64"],"files":{"lib/lib\(id).dylib":"test"}}
    """.utf8).write(to: directory.appending(path: "module.json"))
    #expect(inventory.state(for: module) == .updateAvailable)
    let matchingCatalog = try JSONDecoder().decode(SignedModuleCatalog.self, from: Data("""
    {"schemaVersion":1,"channel":"stable","signed":true,"modules":[
      {"id":"\(id)","displayName":"YAYA 6","kinds":["shiori"],"availability":"candidate","artifacts":[
        {"path":"artifacts/old.zip","sha256":"\(String(repeating: "0", count: 64))","size":1,"architectures":["arm64"],"minimumOS":"14.0","abi":"shiori","version":"\(prefix)\(code)-2","revision":1}
      ]}
    ]}
    """.utf8))
    #expect(try inventory.state(for: #require(matchingCatalog.modules.first)) == .current)
}

@Test(arguments: [("yaya", "Tc574-11", 2), ("yaya-6", "Tc607-2", 2), ("satori", "Mc205-4", 2), ("kawari", "9.1.0", 4)])
func `internal SAORI minimum revisions work offline and follow selected libraries`(id: String, version: String, revision: Int) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let inventory = ModuleCatalogInventory(applicationSupportURL: root)
    #expect(inventory.internalSaoriUpdateRequired(moduleID: id) == nil)
    let directory = root.appending(path: "NativeShiori/\(id)")
    try FileManager.default.createDirectory(at: directory.appending(path: "lib"), withIntermediateDirectories: true)
    let library = directory.appending(path: "lib/lib\(id).dylib")
    try Data().write(to: library)
    func write(_ release: String, _ build: Int) throws {
        try Data("""
        {"schemaVersion":1,"id":"\(id)","version":"\(release)","revision":\(build),"abi":"shiori","minimumOS":"14.0","architectures":["\(inventory.architecture)"],"files":{"lib/lib\(id).dylib":"test"}}
        """.utf8).write(to: directory.appending(path: "module.json"))
    }
    try write(version, revision - 1)
    #expect(inventory.internalSaoriUpdateRequired(moduleID: id)?.label == "\(version)-r\(revision)")
    #expect(inventory.internalSaoriUpdateRequired(libraryURL: library)?.moduleID == id)
    #expect(inventory.internalSaoriUpdateRequired(libraryURL: directory.appending(path: "lib/custom.dylib")) == nil)
    try write(version, revision)
    #expect(inventory.internalSaoriUpdateRequired(moduleID: id) == nil)
    #expect(inventory.internalSaoriUpdateRequired(libraryURL: library) == nil)
    try write(version, revision + 1)
    #expect(inventory.internalSaoriUpdateRequired(moduleID: id) == nil)
    try write("1.0.0", 100)
    #expect(inventory.internalSaoriUpdateRequired(moduleID: id) != nil)
}
