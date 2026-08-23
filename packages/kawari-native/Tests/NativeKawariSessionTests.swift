import AppKit
import Foundation
import Testing
import UtataneCore
@testable import UtataneKawariNative
import UtataneShiori

@Suite(.serialized)
struct NativeKawariSessionTests {
    @Test
    @MainActor
    func `native textcopy2 SAORI writes the macOS pasteboard`() {
        let marker = "Utatane textcopy2 \(UUID().uuidString)"
        let request = "EXECUTE SAORI/1.0\r\n"
            + "Charset: Shift_JIS\r\n"
            + "Argument0: \(marker)\r\n"
            + "Argument1: 1\r\n\r\n"
        let response = nativeTextCopySaoriResponse(for: request)

        #expect(response.contains("Result: \(marker)"))
        #expect(NSPasteboard.general.string(forType: .string) == marker)
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

    @Test func `loads a legacy kawari ini ghost and answers OnBoot`() throws {
        let master = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Content/Local/Ghosts/mayura/ghost/master", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: master.appending(path: "kawari.ini").path) else { return }

        #expect(NativeKawariPersonalityEngine.supports(masterDirectoryURL: master))
        let session = try NativeKawariSession(masterDirectoryURL: master)
        let response = try session.request(GhostEventShioriAdapter().request(for: .boot))
        #expect((200 ..< 300).contains(response.statusCode))
        #expect(response.value?.isEmpty == false)
        #expect(response.value?.contains("�") != true)
    }
}
