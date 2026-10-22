import Foundation
import Testing
@testable import UtataneContent

@Test func `finds SSP in Wine CrossOver and Whisky without copying content`() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = [
        ".wine/drive_c/SSP",
        "Library/Application Support/CrossOver/Bottles/Japanese/drive_c/Program Files/SSP",
        "Library/Containers/com.isaacmarovitz.Whisky/Bottles/test/drive_c/users/wamo/Desktop/SSP"
    ]
    for path in paths {
        let root = home.appending(path: path)
        try FileManager.default.createDirectory(at: root.appending(path: "GhOsT"), withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: "SSP.EXE"))
    }
    let result = SSPInstallationLocator(home: home).locate()
    #expect(Set(result.map { $0.directory.resolvingSymlinksInPath().path }) == Set(paths.map { home.appending(path: $0).resolvingSymlinksInPath().path }))
    #expect(result.map(\.environment) == ["Wine", "CrossOver (Japanese)", "Whisky (test)"])
}

@Test func `SSP detection skips linked trees incomplete roots and excluded directories`() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let drive = home.appending(path: ".wine/drive_c")
    try FileManager.default.createDirectory(at: drive.appending(path: "incomplete/ghost"), withIntermediateDirectories: true)
    let outside = home.appending(path: "outside")
    try FileManager.default.createDirectory(at: outside.appending(path: "ghost"), withIntermediateDirectories: true)
    try Data().write(to: outside.appending(path: "ssp.exe"))
    try FileManager.default.createSymbolicLink(at: drive.appending(path: "linked"), withDestinationURL: outside)
    try FileManager.default.createDirectory(at: drive.appending(path: "Windows/SSP/ghost"), withIntermediateDirectories: true)
    try Data().write(to: drive.appending(path: "Windows/SSP/ssp.exe"))
    #expect(SSPInstallationLocator(home: home).locate().isEmpty)
    try FileManager.default.removeItem(at: drive)
    try FileManager.default.createSymbolicLink(at: drive, withDestinationURL: outside)
    #expect(SSPInstallationLocator(home: home).locate().isEmpty)
}

@Test func `SSP detection respects depth and directory limits`() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appending(path: ".wine/drive_c/nested/SSP")
    try FileManager.default.createDirectory(at: root.appending(path: "ghost"), withIntermediateDirectories: true)
    try Data().write(to: root.appending(path: "ssp.exe"))
    #expect(SSPInstallationLocator(home: home, maximumDepth: 1).locate().isEmpty)
    #expect(SSPInstallationLocator(home: home, maximumDirectories: 1).locate().isEmpty)
    #expect(SSPInstallationLocator(home: home, maximumDepth: 2).locate().count == 1)
}
