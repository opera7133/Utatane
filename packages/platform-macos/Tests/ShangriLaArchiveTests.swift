import Foundation
import Testing
import UtataneContent
import UtataneCore
import UtataneModuleHost
import UtataneShell
import UtataneShiori

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_TEST_YUHNA_ARCHIVE"] != nil))
func `installs a real ZIP and runs its native Yuhna dictionary`() async throws {
    let env = ProcessInfo.processInfo.environment
    let archive = try URL(filePath: #require(env["UTATANE_TEST_YUHNA_ARCHIVE"]))
    let module = try URL(filePath: #require(env["UTATANE_YUHNA_MODULE"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "yuhna-install-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let roots = NarInstallationRoots(ghostsDirectory: root.appending(path: "Ghosts"),
                                     balloonsDirectory: root.appending(path: "Balloons"))
    let result = try NarInstaller().install(archiveURL: archive, roots: roots)
    let item = try #require(result.items.first)
    #expect(item.type == .ghost)
    _ = try ShellLoader().load(from: item.url.appending(path: "shell/master"))
    let master = item.url.appending(path: "ghost/master")
    let resolver = UtataneModuleResolver(environment: ["UTATANE_YUHNA_MODULE": module.path])
    for filename in ["yuhna.dll", "shiori.dll"] {
        let descriptor = try #require(ShioriCatalog.identify(masterDirectory: master, declaredModuleFilename: filename))
        #expect(ConventionalShioriKind(descriptor: descriptor) == .yuhna)
    }
    let selected = try #require(try resolver.moduleURL(for: .yuhna, masterDirectoryURL: master, declaredModuleFilename: "yuhna.dll"))
    let state = root.appending(path: "State")
    let session = try NativeShioriSession(directoryURL: master, moduleURL: selected, stateDirectoryURL: state)
    let adapter = GhostEventShioriAdapter()
    for id in ["OnBoot", "OnAITalk", "OnClose"] {
        let wire = adapter.request(for: .shiori(id: id, references: [:])).serialized()
        let reply = try await ShioriMessageParser.parseResponse(session.requestAsync(wire))
        #expect(reply.statusCode == 200, "\(id)")
        #expect(reply.value?.isEmpty == false, "\(id)")
    }
    let notify = adapter.request(for: .notification(id: "OnNotifyUserInfo", references: [0: "テスト利用者"]))
    _ = try await session.requestAsync(notify.serialized())
    let chooseName = adapter.request(for: .choice(id: "SettingUserName", arguments: []))
    let prompt = try await ShioriMessageParser.parseResponse(session.requestAsync(chooseName.serialized()))
    #expect(prompt.value?.contains("テスト利用者") == true)
    #expect(prompt.value?.contains(#"\![open,inputbox,OnYuhnaUsername,0]"#) == true)
    let enterName = adapter.request(for: SHIORIEventFactory.userInput(id: "OnYuhnaUsername", value: "新しい名前"))
    let confirmation = try await ShioriMessageParser.parseResponse(session.requestAsync(enterName.serialized()))
    #expect(confirmation.value?.contains("「新しい名前」だね") == true)
    try await session.closeAsync()
    let saved = state.appending(path: "yuhna-state.json")
    let persisted = try String(contentsOf: saved, encoding: .utf8)
    #expect(persisted.contains("新しい名前"))
}
