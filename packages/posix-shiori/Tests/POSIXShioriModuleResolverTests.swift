import Foundation
import Testing
@testable import UtatanePOSIXShiori

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
}
