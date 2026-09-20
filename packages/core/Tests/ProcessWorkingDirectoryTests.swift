import Foundation
import Testing
@testable import UtataneCore

@Suite(.serialized)
struct ProcessWorkingDirectoryTests {
    @Test func `uses the requested directory only while running the body`() throws {
        try withExclusiveWorkingDirectory {
            let original = FileManager.default.currentDirectoryPath
            let directory = FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let observed = try ProcessWorkingDirectory.withDirectory(directory) {
                FileManager.default.currentDirectoryPath
            }

            #expect(
                URL(filePath: observed, directoryHint: .isDirectory).resolvingSymlinksInPath()
                    == directory.resolvingSymlinksInPath()
            )
            #expect(FileManager.default.currentDirectoryPath == original)
        }
    }

    @Test func `restores the directory after the body throws`() throws {
        struct ExpectedFailure: Error {}

        try withExclusiveWorkingDirectory {
            let original = FileManager.default.currentDirectoryPath
            let directory = FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            #expect(throws: ExpectedFailure.self) {
                try ProcessWorkingDirectory.withDirectory(directory) {
                    throw ExpectedFailure()
                }
            }
            #expect(FileManager.default.currentDirectoryPath == original)
        }
    }

    private func withExclusiveWorkingDirectory(_ body: () throws -> Void) throws {
        let stableDirectory = URL(filePath: #filePath).deletingLastPathComponent()
        try ProcessWorkingDirectory.withDirectory(stableDirectory, body: body)
    }
}
