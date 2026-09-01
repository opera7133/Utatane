import AppKit
import Foundation
import Testing
import UtataneCore
@testable import UtataneKawariNative
import UtataneShiori

@Suite(.serialized)
struct NativeKawariSessionTests {
    @Test func `translates legacy KAWARI if false branches`() {
        #expect(
            NativeKawariSession.translateLegacyComparisonOperators(in:
                NativeKawariSession.translateLegacyIfSyntax(
                    in: #"$(if $([ ${value} -eq 1 ]) ${yes} ${no})"#
                )) == #"$(if $([ ${value} == 1 ]) ${yes} else ${no})"#
        )
        #expect(NativeKawariSession.translateLegacyExpressionSyntax(
            in: #"$(if $([ ${value} == 1 ]) ${yes})"#
        ) == #"$(if $[ ${value} == 1 ] ${yes})"#)
        #expect(NativeKawariSession.translateLegacyIfSyntax(
            in: #"$(set value 1 ; if $([ ${value} -eq 1 ]) ${yes})"#
        ) == #"$(set value 1)$(if $([ ${value} -eq 1 ]) ${yes})"#)
    }

    @Test func `loads legacy dictionaries through Windows path separators`() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "utatane-kawari-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appending(path: "nested", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let config = "dict : nested\\events.txt\r\n"
        let dictionary = #"event.OnBoot : \0nested dictionary loaded\e"# + "\r\n"
        try #require(config.data(using: .shiftJIS)).write(to: root.appending(path: "kawari.ini"))
        try #require(dictionary.data(using: .shiftJIS)).write(to: nested.appending(path: "events.txt"))

        let session = try NativeKawariSession(masterDirectoryURL: root)
        let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect(response.value?.contains("nested dictionary loaded") == true)
    }

    @Test
    @MainActor
    func `native textcopy2 SAORI writes an isolated pasteboard`() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous contents", forType: .string)
        let marker = "Utatane textcopy2 \(UUID().uuidString)"
        let request = "EXECUTE SAORI/1.0\r\n"
            + "Charset: Shift_JIS\r\n"
            + "Argument0: \(marker)\r\n"
            + "Argument1: 1\r\n\r\n"
        let response = nativeTextCopySaoriResponse(for: request, pasteboardName: pasteboard.name.rawValue)

        #expect(response.contains("Result: \(marker)"))
        #expect(pasteboard.string(forType: .string) == marker)
    }

    @Test func `native KAWARI loads COLORS beta and answers OnBoot`() throws {
        let master = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/Ghosts/colors/ghost/master", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: master.path) else { return }

        let session = try NativeKawariSession(masterDirectoryURL: master)
        let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect((200 ..< 300).contains(response.statusCode))
        #expect(response.value?.contains("COLORS Update") == true)
        #expect(response.value?.contains("�") != true)
    }

    @Test func `detects a KAWARI ghost layout`() {
        let master = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/Ghosts/colors/ghost/master", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: master.path) else { return }
        #expect(NativeKawariPersonalityEngine.supports(masterDirectoryURL: master))
    }

    @Test func `loads a legacy kawari ini ghost and answers OnBoot`() async throws {
        let master = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Content/Local/Ghosts/mayura/ghost/master", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: master.appending(path: "kawari.ini").path) else { return }

        #expect(NativeKawariPersonalityEngine.supports(masterDirectoryURL: master))
        let session = try NativeKawariSession(masterDirectoryURL: master)
        for kind in [
            GhostMouseEvent.Kind.down,
            .up,
            .click,
            .down,
            .up
        ] {
            let incidentalResponse = try session.request(GhostEventShioriAdapter().request(for: .mouse(
                GhostMouseEvent(kind: kind, scope: 0, region: "cap", x: 200, y: 80)
            )))
            #expect(incidentalResponse.value == #"\e"#)
        }
        let initialMenu = try session.request(GhostEventShioriAdapter().request(for: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: "cap",
            x: 200,
            y: 80
        ))))
        #expect(initialMenu.value?.contains("メニュー") == true)
        for (region, marker) in [
            ("face", #"\s[4]"#),
            ("head", #"\s[3]"#),
            ("bust", #"\s[1]"#),
            ("skirt", #"\s[7]"#),
            ("bracelet", #"\s[5]"#)
        ] {
            let response = try session.request(GhostEventShioriAdapter().request(for: .mouse(GhostMouseEvent(
                kind: .doubleClick,
                scope: 0,
                region: region,
                x: 200,
                y: 200
            ))))
            #expect(response.value?.contains(marker) == true, "region: \(region), value: \(response.value ?? "nil")")
            #expect(response.value?.contains("メニュー") != true, "region: \(region), value: \(response.value ?? "nil")")
        }
        let engine = try NativeKawariPersonalityEngine(masterDirectoryURL: master)
        for kind in [
            GhostMouseEvent.Kind.down,
            .up,
            .click,
            .down,
            .up
        ] {
            let script = try await engine.handle(event: .mouse(
                GhostMouseEvent(kind: kind, scope: 0, region: "cap", x: 200, y: 80)
            ))
            #expect(script == nil)
        }
        let engineMenu = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: "cap",
            x: 200,
            y: 80
        )))
        #expect(engineMenu?.rawValue.contains("メニュー") == true)
        let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect((200 ..< 300).contains(response.statusCode))
        #expect(response.value?.isEmpty == false)
        #expect(response.value?.contains("�") != true)
        #expect(response.value?.contains("; if") != true)
        #expect(response.value?.contains(#"\1\s[10]"#) == true)
        #expect(response.value?.hasSuffix(#"\e"#) == true)

        let restore = try session.request(GhostEventShioriAdapter().request(for: .shiori(
            id: "OnSurfaceRestore",
            references: [0: "5", 1: "10"]
        )))
        #expect(restore.value?.contains(#"\0\s[0]"#) == true)
        #expect(restore.value?.contains(#"\1\s[10]"#) == true, "value: \(restore.value ?? "nil")")
        #expect(restore.value?.hasSuffix(#"\e"#) == true)

        let menu = try session.request(GhostEventShioriAdapter().request(for: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: "cap",
            x: 200,
            y: 80
        ))))
        #expect(menu.value?.contains("メニュー") == true)

        let choice = try session.request(GhostEventShioriAdapter().request(for: .choice(id: "menu.status", arguments: [])))
        #expect(choice.value?.isEmpty == false)

        let randomTalk = try session.request(GhostEventShioriAdapter().request(for: .randomTalk))
        #expect(randomTalk.value?.isEmpty == false)
    }

    @Test func `dot sakura loads nested event dictionaries`() throws {
        let master = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Content/Local/Ghosts/dot_sakura/ghost/master", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: master.appending(path: "kawari.ini").path) else { return }

        let session = try NativeKawariSession(masterDirectoryURL: master)
        let boot = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect(boot.value?.isEmpty == false, "value: \(boot.value ?? "nil")")
        let menu = try session.request(GhostEventShioriAdapter().request(for: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: "Bust",
            x: 100,
            y: 100
        ))))
        #expect(menu.value?.contains("偽ＡＩトーク") == true, "value: \(menu.value ?? "nil")")
        #expect(menu.value?.contains(#"\q["#) == true, "value: \(menu.value ?? "nil")")
    }
}
