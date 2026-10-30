import Foundation
import Testing
import UtataneCore
@testable import UtatanePOSIXShiori
import UtataneShiori

@Test func `detects an Aosora ghost layout`() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appending(path: "ghost.asproj"))

    #expect(POSIXShioriModuleResolver().kind(for: root) == .aosora)
}

@Test func `uses an existing explicit Aosora module override`() throws {
    let module = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .notDirectory)
    try Data().write(to: module)
    defer { try? FileManager.default.removeItem(at: module) }

    let resolved = POSIXShioriModuleResolver().moduleURL(
        for: .aosora,
        masterDirectoryURL: module.deletingLastPathComponent(),
        environment: ["UTATANE_AOSORA_MODULE": module.path]
    )
    #expect(resolved == module)
}

@Test func `installed Aosora demo answers OnBoot through native SHIORI`() throws {
    let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    let master = applicationSupport.appending(
        path: "Utatane/Ghosts/demo/ghost/master",
        directoryHint: .isDirectory
    )
    let resolver = POSIXShioriModuleResolver()
    guard FileManager.default.fileExists(atPath: master.path),
          let module = resolver.moduleURL(for: .aosora, masterDirectoryURL: master)
    else { return }

    let session = try POSIXShioriSession(
        masterDirectoryURL: master,
        moduleURL: module,
        kind: .aosora
    )
    let response = try session.request(
        "GET SHIORI/3.0\r\n"
            + "Charset: UTF-8\r\n"
            + "Sender: Utatane\r\n"
            + "SecurityLevel: local\r\n"
            + "ID: OnBoot\r\n\r\n"
    )
    #expect(response.hasPrefix("SHIORI/3.0 2"))
    #expect(!response.contains("�"))

    let adapter = GhostEventShioriAdapter()
    let menu = try session.request(adapter.request(for: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: nil,
        x: 100,
        y: 100
    ))))
    #expect(menu.statusCode == 200)
    #expect(menu.value?.contains("何か喋って") == true)
    for choiceID in ["OnChagneTalkInterval", "OnChangeUserName", "OnItemList", "OnMenuClose"] {
        let choiceResponse = try session.request(adapter.request(for: .choice(id: choiceID, arguments: [])))
        #expect(choiceResponse.statusCode == 200)
        #expect(choiceResponse.value?.isEmpty == false)
    }
    let randomTalk = try session.request(adapter.request(for: .choice(id: "ランダムトーク", arguments: [])))
    #expect(randomTalk.statusCode == 200)
    #expect(randomTalk.value?.isEmpty == false)
}

@Test(arguments: ["aosora/libaosora.dylib", "aosora/lib/libaosora.dylib"])
func `manual Aosora layout needs no Modules manifest`(relative: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let native = root.appending(path: "NativeShiori")
    let library = native.appending(path: relative)
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: master.appending(path: "ghost.asproj"))
    try Data().write(to: library)
    let resolver = POSIXShioriModuleResolver(applicationSupportURL: native, bundledResourcesURL: nil)
    #expect(resolver.moduleURL(for: .aosora, masterDirectoryURL: master, environment: [:]) == library)
    let local = master.appending(path: "shiori.dylib")
    try Data().write(to: local)
    #expect(resolver.moduleURL(for: .aosora, masterDirectoryURL: master, environment: [:]) == local)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_AOSORA_LOCAL_GHOST"] != nil))
func `local manual Aosora loads a copied real ghost`() throws {
    let source = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_AOSORA_LOCAL_GHOST"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "蒼空 integration \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: source, to: root)
    let resolver = POSIXShioriModuleResolver()
    let module = try #require(resolver.moduleURL(for: .aosora, masterDirectoryURL: root))
    let session = try POSIXShioriSession(masterDirectoryURL: root, moduleURL: module, kind: .aosora)
    defer { session.close() }
    let response = try session.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\nSecurityLevel: local\r\n\r\n")
    #expect(response.hasPrefix("SHIORI/3.0 200"))
    #expect(response.contains("Value: "))
}

@Test func `Aosora searches beside a declared DLL in a subfolder`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appending(path: "engine/shiori.dylib")
    try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: library)
    try "shiori,engine/shiori.dll\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    let resolver = POSIXShioriModuleResolver(applicationSupportURL: root.appending(path: "NativeShiori"), bundledResourcesURL: nil)
    #expect(resolver.moduleURL(for: .aosora, masterDirectoryURL: root, environment: [:]) == library)
}
