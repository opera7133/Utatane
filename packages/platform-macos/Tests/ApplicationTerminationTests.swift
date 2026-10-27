import Foundation
import Testing
@testable import UtatanePlatformMacOS

@Suite(.serialized)
struct ApplicationTerminationTests {
    @MainActor private final class Progress {
        var completed = false
    }

    @Test func `termination waits for the initiating main actor job to return`() async {
        let responsive = await withCheckedContinuation { continuation in
            Task { @MainActor in
                let progress = Progress()
                ApplicationTermination.request {
                    // The initiating executor job must be released before AppKit
                    // can enter its terminateLater nested loop.
                    continuation.resume(returning: progress.completed)
                }
                progress.completed = true
            }
        }
        #expect(responsive)
    }

    @Test func `repeated termination requests enter only one nested run loop`() async {
        let count = await withCheckedContinuation { continuation in
            Task { @MainActor in
                var count = 0
                ApplicationTermination.request {
                    count += 1
                    ApplicationTermination.request { count += 1 }
                    continuation.resume(returning: count)
                }
                ApplicationTermination.request { count += 1 }
            }
        }
        #expect(count == 1)
    }

    @Test func `actual AppKit termination completes cleanup in an isolated process`() async throws {
        let script = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../Scripts/test-application-termination.py").standardizedFileURL
        let (status, message) = try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/python3")
            process.arguments = [script.path]
            let output = Pipe()
            process.standardOutput = output; process.standardError = output
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }.value
        #expect(status == 0, Comment(rawValue: message))
    }
}
