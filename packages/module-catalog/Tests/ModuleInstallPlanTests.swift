import Foundation
import Testing
import UtataneCore
@testable import UtataneModuleCatalog
import UtataneNetwork

private func requirementCatalog() throws -> SignedModuleCatalog {
    let modules: [[String: Any]] = [
        ["id": "satori", "displayName": "SATORI", "kinds": ["shiori"], "availability": "candidate"],
        ["id": "httpc", "displayName": "httpc", "kinds": ["saori"], "availability": "candidate"],
        ["id": "clipcopy", "displayName": "clipcopy", "kinds": ["saori"], "availability": "instructions-only"],
        ["id": "oldcpu", "displayName": "oldcpu", "kinds": ["saori"], "availability": "candidate"],
        ["id": "plugin", "displayName": "plugin", "kinds": ["plugin"], "availability": "candidate"]
    ].map { item in
        var item = item
        item["artifacts"] = item["availability"] as? String == "instructions-only" ? [] : [["path": "artifacts/\(item["id"]!).zip", "size": 1, "sha256": String(repeating: "0", count: 64), "architectures": item["id"] as? String == "oldcpu" ? ["other"] : ["arm64", "x86_64"], "minimumOS": "14.0", "abi": "test", "version": "1", "revision": 1]]
        return item
    }
    return try JSONDecoder().decode(SignedModuleCatalog.self, from: JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "channel": "stable", "signed": true, "modules": modules]))
}

@Test func `mixed requirements retain downloadable entries and explain manual unsupported and unknown ones`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let plan = try ModuleInstallPlan(moduleIDs: ["satori", "httpc", "httpc", "clipcopy", "oldcpu", "absent", "plugin"], catalog: requirementCatalog(), inventory: .init(applicationSupportURL: root))
    #expect(plan.moduleIDs == ["satori", "httpc"])
    #expect(plan.unavailable.map(\.reason) == [.manualOnly, .unsupportedPlatform, .notInCatalog, .unsupportedKind])
}

@Test func `explicit SHIORI SAORI declarations combine with registrations even without bundled DLLs`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "ghost/master")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data(#"{"schemaVersion":1,"modules":[{"id":"httpc","kind":"saori"},{"id":"clipcopy","kind":"saori"}]}"#.utf8).write(to: master.appending(path: "utatane-modules.json"))
    try "＠SAORI\nコピー,clipcopy.dll\nIP,saori_ip.dll\n無関係,../../outside.dll\n＠OTHER\n無視,textcopy.dll\n".write(to: master.appending(path: "satori_conf.txt"), atomically: true, encoding: .utf8)
    let ghost = InstalledGhost(name: "probe", rootDirectory: root, defaultShellDirectory: root, shioriFilename: "satori.dll")
    let missing = GhostModuleRequirements().unresolved(for: ghost, applicationSupportURL: root.appending(path: "managed"))
    #expect(Set(missing.map(\.id)) == ["httpc", "clipcopy", "satori", "saori-ip"])
    #expect(missing.count == 4)
    #expect(missing.allSatisfy { $0.sourceDLLURL == nil })
    for invalid in [#"{"schemaVersion":1,"modules":[{"id":"../escape","kind":"saori"}]}"#, #"{"schemaVersion":1,"modules":[{"id":"plugin","kind":"plugin"}]}"#, #"{"schemaVersion":2,"modules":[]}"#] {
        try Data(invalid.utf8).write(to: master.appending(path: "utatane-modules.json"))
        #expect(throws: GhostModuleDeclaration.Failure.self) { try GhostModuleDeclaration.read(from: master) }
    }
}

@Test func `a declaration cannot install a module of a different kind and unknown DLLs trigger catalog discovery`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let master = root.appending(path: "ghost/master")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let plan = try ModuleInstallPlan(moduleIDs: ["satori"], catalog: requirementCatalog(), inventory: .init(applicationSupportURL: root), requiredKinds: ["satori": "SAORI"])
    #expect(plan.moduleIDs.isEmpty)
    #expect(plan.unavailable.first?.reason == .unsupportedKind)
    let ghost = InstalledGhost(name: "probe", rootDirectory: root, defaultShellDirectory: root, shioriFilename: "shiori.dll")
    let scanner = GhostModuleRequirements()
    #expect(!scanner.needsCatalogDiscovery(for: ghost, applicationSupportURL: root))
    try Data().write(to: master.appending(path: "unknown-helper.dll"))
    #expect(scanner.needsCatalogDiscovery(for: ghost, applicationSupportURL: root))
    #expect(scanner.unresolved(for: ghost, applicationSupportURL: root).allSatisfy { $0.kind != "SAORI" })
    try Data().write(to: master.appending(path: "libunknown-helper.dylib"))
    #expect(!scanner.needsCatalogDiscovery(for: ghost, applicationSupportURL: root))
}
