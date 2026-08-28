import Foundation
import Testing
@testable import UtatanePlatformMacOS

@MainActor
struct ApplicationRelauncherTests {
    @Test func `relaunch waits for exit and forwards exact bundle and explicit environment`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let opener = directory.appending(path: "open 'with spaces'")
        try "#!/bin/sh\nprintf '%s\\0' \"$@\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)
        let input = Pipe()
        let parent = Process()
        parent.executableURL = URL(filePath: "/bin/cat")
        parent.standardInput = input
        parent.standardOutput = FileHandle.nullDevice
        try parent.run()
        defer {
            if parent.isRunning {
                parent.terminate()
            }
        }

        let bundleURL = directory.appending(path: "Utatane 日本語 ' $(no-command) `.app")
        let contentRoot = directory.appending(path: "content with ' $literal `values`").path
        let helper = ApplicationRelauncher.makeHelper(
            applicationURL: bundleURL,
            waitingFor: parent.processIdentifier,
            environment: ["UTATANE_CONTENT_ROOT": contentRoot, "UNRELATED_SECRET": "not forwarded"],
            openExecutable: opener,
            attempts: 100
        )
        let output = Pipe()
        helper.standardOutput = output
        try helper.run()
        defer {
            if helper.isRunning {
                helper.terminate()
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(parent.isRunning)
        #expect(helper.isRunning)

        try input.fileHandleForWriting.close()
        parent.waitUntilExit()
        helper.waitUntilExit()
        #expect(helper.terminationStatus == 0)
        let arguments = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\0").map(String.init)
        #expect(arguments == ["-n", "-a", bundleURL.path, "--env", "UTATANE_CONTENT_ROOT=\(contentRoot)"])
    }

    @Test func `shutdown that never completes does not start another app`() throws {
        let helper = ApplicationRelauncher.makeHelper(
            applicationURL: URL(filePath: "/unused.app"),
            waitingFor: ProcessInfo.processInfo.processIdentifier,
            openExecutable: URL(filePath: "/usr/bin/true"),
            attempts: 1
        )
        try helper.run()
        helper.waitUntilExit()
        #expect(helper.terminationStatus == 1)
    }

    @Test func `non app process cannot request a restart`() {
        let relauncher = ApplicationRelauncher()
        #expect(throws: CocoaError.self) { try relauncher.restart() }
        #expect(!relauncher.isRestarting)
    }
}
