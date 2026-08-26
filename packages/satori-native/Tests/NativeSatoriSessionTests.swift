import Foundation
import Testing
import UtataneCore
@testable import UtataneSatoriNative
import UtataneShiori

@Suite(.serialized)
struct NativeSatoriSessionTests {
    @Test func `native SATORI accepts surface change for a single character`() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let dictionary = "＊OnBoot\r\n：起動。\r\n"
        try #require(dictionary.data(using: .shiftJIS)).write(
            to: master.appending(path: "dic00_base.txt")
        )

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        _ = try session.request(GhostEventShioriAdapter().request(for: .boot))
        let response = try session.request(GhostEventShioriAdapter().request(for: .shiori(
            id: "OnSurfaceChange",
            references: [0: "0"]
        )))

        #expect((200 ..< 300).contains(response.statusCode))
    }

    @Test func `native SATORI loads memory-na and answers boot`() throws {
        let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let request = GhostEventShioriAdapter().request(for: .boot)
        let response = try session.request(request)
        #expect((200 ..< 300).contains(response.statusCode))
        #expect(response.value?.isEmpty == false)
    }

    @Test func `native SATORI decodes mixed encoding in memory-na dialogue`() throws {
        let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let event = GhostEvent.mouse(.init(
            kind: .doubleClick,
            scope: 0,
            region: "Head",
            x: 100,
            y: 100,
            button: 0
        ))
        let response = try session.request(GhostEventShioriAdapter().request(for: event))
        #expect(response.value?.contains("�") == false)
        #expect(response.value?.contains("静電防止手袋") == true)
        #expect(response.value?.contains("＄メモリ好感度") == false)
        #expect(response.value?.contains("メモリ好感度") == false)

        var strokeResponses: [String] = []
        for offset in 0 ..< 200 {
            let strokeEvent = GhostEvent.mouse(.init(
                kind: .move,
                scope: 0,
                region: "Head",
                x: 100 + offset,
                y: 100,
                button: 0
            ))
            let strokeResponse = try session.request(GhostEventShioriAdapter().request(for: strokeEvent))
            if let value = strokeResponse.value, !value.isEmpty {
                strokeResponses.append(value)
            }
        }
        #expect(!strokeResponses.isEmpty)
        #expect(strokeResponses.allSatisfy { !$0.contains("＄") && !$0.contains("メモリ好感度") })
    }

    @Test func `native SATORI keeps memory-na Memory dialogue intact`() throws {
        let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let event = GhostEvent.mouse(.init(
            kind: .doubleClick,
            scope: 0,
            region: "Memory",
            x: 100,
            y: 100,
            button: 0
        ))
        let response = try session.request(GhostEventShioriAdapter().request(for: event))
        let value = try #require(response.value)
        #expect(value.contains("�") == false)
        #expect(value.contains("素手でメモリを触るのはやめてよね"))
        #expect(value.contains("薄い本的な意味で"))
        #expect(value.contains("壊れちゃいましゅぅ"))
    }

    @Test func `detects SATORI ghost configuration`() {
        let master = repositoryRoot.appending(path: "Content/Local/Ghosts/twin/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(master) else { return }
        #expect(NativeSatoriPersonalityEngine.supports(masterDirectoryURL: master))
    }

    @Test func `native SATORI personality maps boot to SakuraScript`() async throws {
        let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let engine = try NativeSatoriPersonalityEngine(masterDirectoryURL: master)
        let script = try await engine.handle(event: .boot)
        #expect(script?.rawValue.isEmpty == false)
    }

    @Test func `native SATORI does not expose dictionary control lines as dialogue`() throws {
        let source = repositoryRoot.appending(path: "Content/Local/Ghosts/memory-na/ghost/master", directoryHint: .isDirectory)
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let adapter = GhostEventShioriAdapter()
        _ = try session.request(adapter.request(for: .boot))
        for _ in 0 ..< 100 {
            let response = try session.request(adapter.request(for: .randomTalk))
            #expect(response.value?.contains("＄メモリ好感度") != true)
            #expect(response.value?.split(separator: "\n").contains(where: {
                $0.hasPrefix("：") || $0.hasPrefix("＄")
            }) != true)
        }
    }

    @Test func `native SATORI executes bundled SSU without Wine`() throws {
        let source = repositoryRoot.appending(
            path: "packages/satori-native/Sources/CSatoriNative/Vendor/satori/test",
            directoryHint: .isDirectory
        )
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let dictionary = "＊OnNativeSSUTest\r\n：結果は（calc,1＋2）。\r\n"
        let dictionaryData = try #require(dictionary.data(using: .shiftJIS))
        try dictionaryData.write(to: master.appending(path: "dic_utatane_ssu.txt"))

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let request = GhostEventShioriAdapter().request(
            for: .shiori(id: "OnNativeSSUTest", references: [:])
        )
        let response = try session.request(request)
        #expect(response.value?.contains("結果は3。") == true)
    }

    @Test func `native SATORI answers system info SAORI without Wine`() throws {
        let source = repositoryRoot.appending(
            path: "Content/Local/Ghosts/memory-na/ghost/master",
            directoryHint: .isDirectory
        )
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let dictionary = "＊OnNativeSystemInfoTest\r\n：OSは（os_name）、CPUは（cpu_number）個。\r\n"
        let dictionaryData = try #require(dictionary.data(using: .shiftJIS))
        try dictionaryData.write(to: master.appending(path: "dic_utatane_system_info.txt"))

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let request = GhostEventShioriAdapter().request(
            for: .shiori(id: "OnNativeSystemInfoTest", references: [:])
        )
        let response = try session.request(request)
        #expect(response.value?.contains("OSはmacOS") == true)
        #expect(response.value?.contains("CPUは0個") == false)
    }

    @Test func `native SATORI classifies communication keywords without Wine`() throws {
        let source = repositoryRoot.appending(
            path: "Content/Local/Ghosts/sake_kami/ghost/master",
            directoryHint: .isDirectory
        )
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let dictionary = "＊OnNativeKeywordTest\r\n：分類は（kenonoke,GETKEYWORD,お酒が好き,NOCONVERT）。\r\n"
        let dictionaryData = try #require(dictionary.data(using: .shiftJIS))
        try dictionaryData.write(to: master.appending(path: "dic_utatane_keyword.txt"))

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let request = GhostEventShioriAdapter().request(
            for: .shiori(id: "OnNativeKeywordTest", references: [:])
        )
        let response = try session.request(request)
        #expect(response.value?.contains("分類はにほんしゅ。") == true)
    }

    @Test(arguments: ["memory-na", "twin", "sake_kami"])
    func `installed SATORI ghosts answer boot`(_ ghostDirectoryName: String) throws {
        let source = repositoryRoot.appending(
            path: "Content/Local/Ghosts/\(ghostDirectoryName)/ghost/master",
            directoryHint: .isDirectory
        )
        guard hasLocalContent(source) else { return }
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let master = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)

        let session = try NativeSatoriSession(masterDirectoryURL: master)
        let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect((200 ..< 300).contains(response.statusCode))
        if ghostDirectoryName == "twin" {
            #expect(response.value?.contains("\\![embed,OnCallSurface") == true)
            _ = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnSetScope", references: [0: "0"])))
            let surface0 = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnCallSurface", references: [0: "5"])))
            _ = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnSetScope", references: [0: "1"])))
            let surface1 = try session.request(GhostEventShioriAdapter().request(for: .shiori(id: "OnCallSurface", references: [0: "0"])))
            #expect(surface0.value == "\\s[5]")
            #expect(surface1.value == "\\s[10000]")
            let shellChanged = try session.request(GhostEventShioriAdapter().request(for: .shiori(
                id: "OnShellChanged",
                references: [0: "master2nd", 1: "master2nd"]
            )))
            #expect(shellChanged.value?.contains("OnCallSurface") == true)
            let shiftJISContext = ShioriEventContext(charset: "Shift_JIS")
            let setting = try session.request(GhostEventShioriAdapter().request(
                for: .shiori(id: "OnChoiceSelect", references: [0: "追加選択肢設定画面"]),
                context: shiftJISContext
            ))
            #expect(setting.value?.contains("OnSetExTalk") == true)
            let close = try session.request(GhostEventShioriAdapter().request(
                for: .shiori(id: "OnChoiceSelect", references: [0: "閉じる"]),
                context: shiftJISContext
            ))
            #expect(close.value?.isEmpty != false)
        }
    }
}

private let repositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func hasLocalContent(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}
