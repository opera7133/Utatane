import Foundation

public enum FirstDLLAnalysisError: Error, Equatable, Sendable {
    case truncated
    case notPortableExecutable
    case unsupportedMachine(UInt16)
    case notDLL
    case missingCodeSection
    case missingAITXTResource
    case invalidAITXTResource
    case invalidAITXTEncoding
    case invalidAITXTRecordCount(Int)
    case invalidAITXTChoice(Int)
    case unsupportedFIRSTVersion
}

public struct FirstDLLIdentity: Equatable, Sendable {
    public let timestamp: UInt32
    public let imageSize: UInt32
    public let fileSize: Int

    public init(timestamp: UInt32, imageSize: UInt32, fileSize: Int) {
        self.timestamp = timestamp
        self.imageSize = imageSize
        self.fileSize = fileSize
    }
}

public enum FirstKnownEvent: Sendable {
    case onBoot
}

public struct FirstEmbeddedString: Equatable, Sendable {
    public let fileOffset: Int
    public let value: String
    public let codeReferenceOffsets: [Int]

    public init(fileOffset: Int, value: String, codeReferenceOffsets: [Int] = []) {
        self.fileOffset = fileOffset
        self.value = value
        self.codeReferenceOffsets = codeReferenceOffsets
    }

    public var containsSakuraScript: Bool {
        value.contains("\\0") || value.contains("\\1") || value.contains("\\s")
    }
}

/// Reads data from a user-supplied Materia FIRST DLL without loading or executing it.
///
/// FIRST was built with Delphi and stores many constants using Delphi's static
/// `AnsiString` layout: a reference count, a byte length, CP932 bytes, and a NUL.
/// This analyzer deliberately returns only data from the supplied DLL. Utatane does
/// not contain or redistribute the extracted strings.
public struct FirstDLLAnalyzer: Sendable {
    private static let i386Machine: UInt16 = 0x014C
    private static let imageFileDLL: UInt16 = 0x2000
    private static let maximumStringLength = 1 << 20

    let data: Data

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        self.data = data
        try validateHeader()
    }

    public func embeddedStrings() throws -> [FirstEmbeddedString] {
        let code = try codeSection()
        let strings = embeddedStrings(in: code)
        let imageBase = try imageBase()
        let addresses = Dictionary(uniqueKeysWithValues: strings.map { string in
            let relativeOffset = string.fileOffset + 8 - code.fileRange.lowerBound
            let address = imageBase + code.virtualAddress + UInt32(relativeOffset)
            return (address, string.fileOffset)
        })
        var references: [Int: [Int]] = [:]
        guard code.fileRange.count >= 4 else {
            return strings
        }
        for offset in code.fileRange.lowerBound ... code.fileRange.upperBound - 4 {
            guard let candidate = readUInt32(at: offset),
                  let stringOffset = addresses[candidate]
            else {
                continue
            }
            references[stringOffset, default: []].append(offset)
        }
        return strings.map { string in
            FirstEmbeddedString(
                fileOffset: string.fileOffset,
                value: string.value,
                codeReferenceOffsets: references[string.fileOffset, default: []]
            )
        }
    }

    /// Decodes FIRST's user-supplied `AITXT/101` resource without executing the DLL.
    public func decodedAITXTLines() throws -> [String] {
        try FirstAITXTDecoder(data: data).decodeLines()
    }

    public func decodedAITXTRecords() throws -> [FirstAITXTRecord] {
        try FirstAITXTDecoder.records(from: decodedAITXTLines())
    }

    public func identity() throws -> FirstDLLIdentity {
        guard let peOffsetValue = readUInt32(at: 0x3C) else {
            throw FirstDLLAnalysisError.truncated
        }
        let peOffset = Int(peOffsetValue)
        let optionalHeader = peOffset + 24
        guard let timestamp = readUInt32(at: peOffset + 8),
              let imageSize = readUInt32(at: optionalHeader + 56)
        else {
            throw FirstDLLAnalysisError.truncated
        }
        return FirstDLLIdentity(timestamp: timestamp, imageSize: imageSize, fileSize: data.count)
    }

    /// Returns strings referenced by the known handler without embedding their contents.
    /// Address profiles are accepted only for the exact FIRST build they were observed in.
    public func fragments(for event: FirstKnownEvent) throws -> [FirstEmbeddedString] {
        guard try identity() == Self.originalFIRSTIdentity else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        let range: Range<UInt32> = switch event {
        case .onBoot: 0x0047_8D2A ..< 0x0047_9625
        }
        return try embeddedStrings(referencedInVirtualAddressRange: range)
            .filter(\.containsSakuraScript)
    }

    /// Returns the self-contained fallback branch currently used to bootstrap
    /// the native event interpreter. More OnBoot branches are composed from
    /// multiple strings and runtime values and are intentionally not guessed here.
    public func baselineScript(for event: FirstKnownEvent) throws -> String {
        guard try identity() == Self.originalFIRSTIdentity else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        let address: UInt32 = switch event {
        case .onBoot: 0x0048_5EEC
        }
        guard let string = try embeddedString(atVirtualAddress: address),
              string.containsSakuraScript
        else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return string.value
    }

    func knownScript(atVirtualAddress address: UInt32) throws -> String {
        let value = try knownString(atVirtualAddress: address)
        guard FirstEmbeddedString(fileOffset: 0, value: value).containsSakuraScript else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return value
    }

    func knownString(atVirtualAddress address: UInt32) throws -> String {
        guard try identity() == Self.originalFIRSTIdentity,
              let string = try embeddedString(atVirtualAddress: address)
        else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        return string.value
    }

    func knownStringsByVirtualAddress() throws -> [UInt32: String] {
        guard try identity() == Self.originalFIRSTIdentity else {
            throw FirstDLLAnalysisError.unsupportedFIRSTVersion
        }
        let code = try codeSection()
        let base = try imageBase() + code.virtualAddress
        return try Dictionary(uniqueKeysWithValues: embeddedStrings().map { string in
            let dataOffset = string.fileOffset + 8 - code.fileRange.lowerBound
            return (base + UInt32(dataOffset), string.value)
        })
    }

    private static let originalFIRSTIdentity = FirstDLLIdentity(
        timestamp: 0x2A42_5E19,
        imageSize: 0x000E_2000,
        fileSize: 890_880
    )

    private func embeddedStrings(
        referencedInVirtualAddressRange range: Range<UInt32>
    ) throws -> [FirstEmbeddedString] {
        let code = try codeSection()
        let base = try imageBase() + code.virtualAddress
        guard range.lowerBound >= base else { return [] }
        let lower = code.fileRange.lowerBound + Int(range.lowerBound - base)
        let upper = code.fileRange.lowerBound + Int(range.upperBound - base)
        let fileRange = lower ..< min(upper, code.fileRange.upperBound)
        return try embeddedStrings().filter { string in
            string.codeReferenceOffsets.contains(where: fileRange.contains)
        }
    }

    private func embeddedString(atVirtualAddress address: UInt32) throws -> FirstEmbeddedString? {
        let code = try codeSection()
        let base = try imageBase() + code.virtualAddress
        guard address >= base else { return nil }
        let dataOffset = code.fileRange.lowerBound + Int(address - base)
        let headerOffset = dataOffset - 8
        return try embeddedStrings().first(where: { $0.fileOffset == headerOffset })
    }

    private func embeddedStrings(in code: CodeSection) -> [FirstEmbeddedString] {
        let range = code.fileRange
        guard range.count >= 13 else {
            return []
        }

        var result: [FirstEmbeddedString] = []
        var offset = range.lowerBound
        while offset <= range.upperBound - 13 {
            defer { offset += 1 }
            guard readUInt32(at: offset) == UInt32.max,
                  let lengthValue = readUInt32(at: offset + 4)
            else {
                continue
            }
            let length = Int(lengthValue)
            guard length > 0, length <= Self.maximumStringLength else {
                continue
            }
            let bytesStart = offset + 8
            let bytesEnd = bytesStart + length
            guard bytesEnd < range.upperBound,
                  data[bytesEnd] == 0,
                  let value = String(data: data[bytesStart ..< bytesEnd], encoding: .shiftJIS),
                  Self.isPlausibleText(value)
            else {
                continue
            }
            result.append(FirstEmbeddedString(fileOffset: offset, value: value))
            offset = bytesEnd
        }
        return result
    }

    private func validateHeader() throws {
        guard data.count >= 0x40 else {
            throw FirstDLLAnalysisError.truncated
        }
        guard data[0] == 0x4D, data[1] == 0x5A,
              let peOffsetValue = readUInt32(at: 0x3C)
        else {
            throw FirstDLLAnalysisError.notPortableExecutable
        }
        let peOffset = Int(peOffsetValue)
        guard peOffset <= data.count - 24 else {
            throw FirstDLLAnalysisError.truncated
        }
        guard data[peOffset ..< peOffset + 4].elementsEqual([0x50, 0x45, 0, 0]) else {
            throw FirstDLLAnalysisError.notPortableExecutable
        }
        guard let machine = readUInt16(at: peOffset + 4),
              let characteristics = readUInt16(at: peOffset + 22)
        else {
            throw FirstDLLAnalysisError.truncated
        }
        guard machine == Self.i386Machine else {
            throw FirstDLLAnalysisError.unsupportedMachine(machine)
        }
        guard characteristics & Self.imageFileDLL != 0 else {
            throw FirstDLLAnalysisError.notDLL
        }
    }

    private func codeSection() throws -> CodeSection {
        guard let peOffsetValue = readUInt32(at: 0x3C) else {
            throw FirstDLLAnalysisError.truncated
        }
        let coffOffset = Int(peOffsetValue) + 4
        guard let sectionCount = readUInt16(at: coffOffset + 2),
              let optionalHeaderSize = readUInt16(at: coffOffset + 16)
        else {
            throw FirstDLLAnalysisError.truncated
        }
        let sectionTable = coffOffset + 20 + Int(optionalHeaderSize)

        for index in 0 ..< Int(sectionCount) {
            let header = sectionTable + index * 40
            guard header <= data.count - 40 else {
                throw FirstDLLAnalysisError.truncated
            }
            let nameBytes = data[header ..< header + 8].prefix { $0 != 0 }
            guard String(bytes: nameBytes, encoding: .ascii) == "CODE" else {
                continue
            }
            guard let virtualAddress = readUInt32(at: header + 12),
                  let rawSize = readUInt32(at: header + 16),
                  let rawOffset = readUInt32(at: header + 20)
            else {
                throw FirstDLLAnalysisError.truncated
            }
            let lowerBound = Int(rawOffset)
            let upperBound = lowerBound + Int(rawSize)
            guard lowerBound <= upperBound, upperBound <= data.count else {
                throw FirstDLLAnalysisError.truncated
            }
            return CodeSection(
                fileRange: lowerBound ..< upperBound,
                virtualAddress: virtualAddress
            )
        }
        throw FirstDLLAnalysisError.missingCodeSection
    }

    private func imageBase() throws -> UInt32 {
        guard let peOffsetValue = readUInt32(at: 0x3C) else {
            throw FirstDLLAnalysisError.truncated
        }
        let optionalHeader = Int(peOffsetValue) + 24
        guard readUInt16(at: optionalHeader) == 0x010B,
              let imageBase = readUInt32(at: optionalHeader + 28)
        else {
            throw FirstDLLAnalysisError.truncated
        }
        return imageBase
    }

    private func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else {
            return nil
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else {
            return nil
        }
        return UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }

    private static func isPlausibleText(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control && scalar != "\r" && scalar != "\n" && scalar != "\t"
        }
    }
}

private struct CodeSection {
    let fileRange: Range<Int>
    let virtualAddress: UInt32
}
