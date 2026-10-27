import Foundation
import Testing
@testable import UtataneContentValidator

/// Original synthetic ZIP: stored install.txt, then ZIP-LZMA dictionary/shell files.
private let archiveLZMAFixture = "UEsDBBQAAAAAAExbW12/81FLHQAAAB0AAAALAAAAaW5zdGFsbC50eHR0eXBlLGdob3N0Cm5hbWUsQXJjaGl2ZSBMWk1BClBLAwQ/AAIADgBMW1tdpoOtqDYAAAAiAAAAGQAAAGdob3N0L21hc3Rlci9kZXNjcmlwdC50eHQJBAUAXQAAgAAANxhJ/fph1WijtA4fOTat0Rfr2lkP7PGJ6Chc0MPDpxbGWfjnsXOf//enCABQSwMEPwACAA4ATFtbXQAAAAATAAAAAAAAABUAAABnaG9zdC9tYXN0ZXIveWF5YS50eHQJBAUAXQAAgAAAg//7///AAAAAUEsDBD8AAgAOAExbW12AkkO4IAAAAAwAAAAZAAAAc2hlbGwvbWFzdGVyL2Rlc2NyaXB0LnR4dAkEBQBdAACAAAA3GEn9+mIZYHmT4H1ZOWdm///jVwAAUEsDBD8AAgAOAExbW10AAAAAEwAAAAAAAAAZAAAAc2hlbGwvbWFzdGVyL3N1cmZhY2UwLnBuZwkEBQBdAACAAACD//v//8AAAABQSwECFAMUAAAAAABMW1tdv/NRSx0AAAAdAAAACwAAAAAAAAAAAAAAgAEAAAAAaW5zdGFsbC50eHRQSwECPwM/AAIADgBMW1tdpoOtqDYAAAAiAAAAGQAAAAAAAAAAAAAAgAFGAAAAZ2hvc3QvbWFzdGVyL2Rlc2NyaXB0LnR4dFBLAQI/Az8AAgAOAExbW10AAAAAEwAAAAAAAAAVAAAAAAAAAAAAAACAAbMAAABnaG9zdC9tYXN0ZXIveWF5YS50eHRQSwECPwM/AAIADgBMW1tdgJJDuCAAAAAMAAAAGQAAAAAAAAAAAAAAgAH5AAAAc2hlbGwvbWFzdGVyL2Rlc2NyaXB0LnR4dFBLAQI/Az8AAgAOAExbW10AAAAAEwAAAAAAAAAZAAAAAAAAAAAAAACAAVABAABzaGVsbC9tYXN0ZXIvc3VyZmFjZTAucG5nUEsFBgAAAAAFAAUAUQEAAJoBAAAAAA=="

private func withLZMAArchive(_ body: (URL, Data) throws -> Void) throws {
    let data = try #require(Data(base64Encoded: archiveLZMAFixture))
    let root = FileManager.default.temporaryDirectory.appending(path: "LZMA 検証 \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "test.nar")
    try data.write(to: url)
    try body(url, data)
}

@Test func `archive validator accepts mixed stored and LZMA entries including empty files`() throws {
    try withLZMAArchive { url, _ in
        let report = ContentArchiveValidator().validate(archiveURL: url)
        #expect(report.ghostName == "Archive LZMA")
        #expect(report.shioriAssessment?.identifier == "yaya")
        #expect(!report.diagnostics.contains { $0.code.hasPrefix("archive.") })
    }
}

@Test func `archive LZMA still enforces declared size count and time limits`() throws {
    try withLZMAArchive { url, _ in
        let size = ContentArchiveValidator(limits: .init(maximumExtractedBytes: 8)).validate(archiveURL: url)
        #expect(size.diagnostics.first?.code == "archive.extracted-too-large")
        let count = ContentArchiveValidator(limits: .init(maximumEntryCount: 1)).validate(archiveURL: url)
        #expect(count.diagnostics.first?.code == "archive.too-many-entries")
        let time = ContentArchiveValidator(limits: .init(timeout: 0)).validate(archiveURL: url)
        #expect(time.diagnostics.first?.code == "archive.timeout")
    }
}

private func little32(_ data: Data, _ index: Int) -> Int {
    Int(data[index]) | Int(data[index + 1]) << 8 | Int(data[index + 2]) << 16 | Int(data[index + 3]) << 24
}

private func firstLZMARecord(_ data: Data) throws -> (central: Int, local: Int, payload: Int) {
    let recordOffset = (0 ..< data.count - 46).first { offset in
        little32(data, offset) == 0x0201_4B50 && data[offset + 10] == 14
    }
    let central = try #require(recordOffset)
    let local = little32(data, central + 42)
    let payload = local + 30 + Int(data[local + 26]) + Int(data[local + 27]) * 256 + Int(data[local + 28]) + Int(data[local + 29]) * 256
    return (central, local, payload)
}

@Test(arguments: ["crc", "stream", "dictionary", "size", "local-method", "traversal"])
func `archive LZMA rejects corrupt or unsafe streams`(kind: String) throws {
    try withLZMAArchive { url, original in
        var data = original
        let record = try firstLZMARecord(data)
        switch kind {
        case "crc": data[record.central + 16] ^= 0x80; data[record.local + 14] ^= 0x80
        case "stream": data[record.payload + 10] ^= 0xFF
        case "dictionary": data.replaceSubrange(record.payload + 5 ..< record.payload + 9, with: [0xFF, 0xFF, 0xFF, 0x7F])
        case "size":
            data.replaceSubrange(record.central + 24 ..< record.central + 28, with: [1, 0, 0, 0])
            data.replaceSubrange(record.local + 22 ..< record.local + 26, with: [1, 0, 0, 0])
        case "local-method": data[record.local + 8] = 8
        default:
            let name = Data("../xx/master/descript.txt".utf8)
            data.replaceSubrange(record.central + 46 ..< record.central + 46 + name.count, with: name)
            data.replaceSubrange(record.local + 30 ..< record.local + 30 + name.count, with: name)
        }
        try data.write(to: url)
        let report = ContentArchiveValidator().validate(archiveURL: url)
        #expect(report.errorCount == 1)
        #expect(report.diagnostics.first?.code.hasPrefix("archive.") == true)
        if kind == "traversal" {
            #expect(report.diagnostics.first?.code == "archive.unsafe-entry")
        }
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appending(path: "xx/master/descript.txt").path))
    }
}
