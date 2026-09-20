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
