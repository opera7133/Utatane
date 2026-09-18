import Foundation
import Testing
@testable import UtataneContentValidator
import ZIPFoundation

@Test
func `validates a ghost in a nested NAR directory`() throws {
    let archiveURL = try makeArchive(entries: [
        ("download/ghost/master/descript.txt", Data("name,Archive Ghost\nshiori,yaya.dll\n".utf8), .file),
        ("download/ghost/master/yaya.txt", Data(), .file),
        ("download/shell/master/descript.txt", Data("name,Master\n".utf8), .file),
        ("download/shell/master/surface0.png", Data(), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.ghostName == "Archive Ghost")
    #expect(report.rootPath == archiveURL.path)
    #expect(report.shioriAssessment?.identifier == "yaya")
    #expect(report.shioriAssessment?.supportStatus == .supported)
    #expect(!report.diagnostics.contains { $0.code.hasPrefix("archive.") })
}

@Test
func `normalizes Windows separators in archive paths`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost\\master\\descript.txt", Data("name,Backslash\nshiori,yaya.dll\n".utf8), .file),
        ("ghost\\master\\yaya.txt", Data(), .file),
        ("shell\\master\\descript.txt", Data("name,Master\n".utf8), .file),
        ("shell\\master\\surface0.png", Data(), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.ghostName == "Backslash")
    #expect(report.shioriAssessment?.identifier == "yaya")
}

@Test
func `rejects path traversal before extraction`() throws {
    let archiveURL = try makeArchive(entries: [
        ("../outside.txt", Data("unsafe".utf8), .file),
        ("ghost/master/descript.txt", Data("name,Unsafe\n".utf8), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "archive.unsafe-entry")
}

@Test
func `enforces declared extracted size limit`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data("name,Too large\n".utf8), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(maximumExtractedBytes: 8)

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "archive.extracted-too-large")
}

@Test
func `enforces individual entry size limit`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data(repeating: 0x41, count: 32), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(maximumEntryBytes: 16)

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.diagnostics.first?.code == "archive.entry-too-large")
}

@Test
func `enforces text file size limit`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data(repeating: 0x41, count: 32), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(maximumEntryBytes: 64, maximumTextFileBytes: 16)

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.diagnostics.first?.code == "archive.text-file-too-large")
}

@Test
func `enforces total text size limit`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/one.dic", Data(repeating: 0x41, count: 12), .file),
        ("ghost/master/two.dic", Data(repeating: 0x42, count: 12), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(
        maximumEntryBytes: 32,
        maximumTextFileBytes: 16,
        maximumTextBytes: 20
    )

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.diagnostics.first?.code == "archive.text-files-too-large")
}

@Test
func `rejects deeply nested paths`() throws {
    let archiveURL = try makeArchive(entries: [
        ("one/two/three/file.bin", Data(), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(maximumPathComponents: 3)

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.diagnostics.first?.code == "archive.path-too-deep")
}

@Test
func `limits implicit parent directories`() throws {
    let archiveURL = try makeArchive(entries: [
        ("one/two/file.bin", Data(), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    let limits = ContentArchiveValidationLimits(maximumDirectoryCount: 1)

    let report = ContentArchiveValidator(limits: limits).validate(archiveURL: archiveURL)

    #expect(report.diagnostics.first?.code == "archive.too-many-directories")
}

@Test
func `rejects archives containing more than one ghost`() throws {
    let archiveURL = try makeArchive(entries: [
        ("one/ghost/master/descript.txt", Data("name,One\n".utf8), .file),
        ("one/shell/master/descript.txt", Data("name,Master\n".utf8), .file),
        ("two/ghost/master/descript.txt", Data("name,Two\n".utf8), .file),
        ("two/shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "archive.multiple-ghosts")
}

@Test
func `rejects symbolic links`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data("name,Link\n".utf8), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file),
        ("ghost/master/link", Data("../outside".utf8), .symlink)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "archive.unsupported-entry")
}

@Test
func `rejects encrypted ZIP entries during preflight`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data("name,Encrypted\n".utf8), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }
    var data = try Data(contentsOf: archiveURL)
    let centralSignature = Data([0x50, 0x4B, 0x01, 0x02])
    guard let centralRange = data.range(of: centralSignature) else {
        Issue.record("central directory entry was not found")
        return
    }
    data[centralRange.lowerBound + 8] |= 1
    try data.write(to: archiveURL)

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)

    #expect(report.errorCount == 1)
    #expect(report.diagnostics.first?.code == "archive.unsupported-entry")
    #expect(report.diagnostics.first?.message.contains("暗号化") == true)
}

@Test
func `does not expose temporary extraction paths in diagnostics`() throws {
    let archiveURL = try makeArchive(entries: [
        ("ghost/master/descript.txt", Data("name,Broken encoding\n".utf8), .file),
        ("shell/master/descript.txt", Data("name,Master\n".utf8), .file),
        ("shell/master/surfaces.txt", Data([0xFF]), .file)
    ])
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let report = ContentArchiveValidator().validate(archiveURL: archiveURL)
    let diagnostic = try #require(report.diagnostics.first { $0.code == "shell.load" })

    #expect(diagnostic.message.contains("/tmp/") == false)
    #expect(diagnostic.message.contains("utatane-validate-") == false)
    #expect(diagnostic.message.contains("shell/master/surfaces.txt"))
}

private func makeArchive(entries: [(String, Data, Entry.EntryType)]) throws -> URL {
    let archiveURL = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).nar")
    do {
        let archive = try Archive(url: archiveURL, accessMode: .create)
        for (path, data, type) in entries {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count)) { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                return start < end ? data.subdata(in: start ..< end) : Data()
            }
        }
    }
    return archiveURL
}
