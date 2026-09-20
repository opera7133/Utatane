import Foundation

public struct FirstAITXTRecord: Equatable, Sendable {
    public let phrase: String
    public let directives: [String]
    public let relatedTerms: [String]

    public init(phrase: String, directives: [String], relatedTerms: [String]) {
        self.phrase = phrase
        self.directives = directives
        self.relatedTerms = relatedTerms
    }
}

struct FirstAITXTDecoder {
    /// Captured at the second seed call in the original FIRST AITXT decoder.
    /// It is derived deterministically from FIRST's fixed initial seed (0x265d).
    static let resourceSeed: UInt32 = 266_150_414

    let data: Data

    func decodeLines() throws -> [String] {
        let resource = try aitxtResource()
        let decoded = Self.decodeResource(resource)
        guard let text = String(data: decoded, encoding: .shiftJIS) else {
            throw FirstDLLAnalysisError.invalidAITXTEncoding
        }
        var lines = text.components(separatedBy: "\r\n")
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    static func decodeResource(_ resource: Data) -> Data {
        var random = OriginalMT19937(seed: resourceSeed)
        return Data(resource.reversed().map { byte in
            byte ^ UInt8(truncatingIfNeeded: random.next(in: 0x7FFF_FFFF))
        })
    }

    static func records(from lines: [String]) throws -> [FirstAITXTRecord] {
        guard lines.count.isMultiple(of: 3) else {
            throw FirstDLLAnalysisError.invalidAITXTRecordCount(lines.count)
        }
        return stride(from: 0, to: lines.count, by: 3).map { index in
            FirstAITXTRecord(
                phrase: lines[index],
                directives: commaSeparated(lines[index + 1]),
                relatedTerms: commaSeparated(lines[index + 2])
            )
        }
    }

    private static func commaSeparated(_ value: String) -> [String] {
        value.isEmpty ? [] : value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    private func aitxtResource() throws -> Data {
        guard let peOffset = uint32(at: 0x3C).map(Int.init) else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        let coff = peOffset + 4
        guard let sectionCount = uint16(at: coff + 2),
              let optionalSize = uint16(at: coff + 16)
        else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        let optional = coff + 20
        guard uint16(at: optional) == 0x010B,
              let resourceRVA = uint32(at: optional + 112),
              resourceRVA != 0
        else {
            throw FirstDLLAnalysisError.missingAITXTResource
        }
        let sections = try sections(at: optional + Int(optionalSize), count: Int(sectionCount))
        guard let resourceBase = fileOffset(forRVA: resourceRVA, sections: sections) else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        let type = try directoryEntry(
            at: resourceBase,
            base: resourceBase,
            matchingName: "AITXT"
        )
        let identifier = try directoryEntry(at: type, base: resourceBase, matchingID: 101)
        let language = try firstDirectoryEntry(at: identifier, base: resourceBase)
        guard let resourceDataRVA = uint32(at: language),
              let size = uint32(at: language + 4),
              let start = fileOffset(forRVA: resourceDataRVA, sections: sections)
        else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        let end = start + Int(size)
        guard start <= end, end <= data.count else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        return Data(data[start ..< end])
    }

    private func directoryEntry(at offset: Int, base: Int, matchingName name: String) throws -> Int {
        try directoryEntry(at: offset, base: base) { nameValue, _ in
            guard nameValue & 0x8000_0000 != 0 else { return false }
            return resourceName(at: base + Int(nameValue & 0x7FFF_FFFF)) == name
        }
    }

    private func directoryEntry(at offset: Int, base: Int, matchingID identifier: UInt32) throws -> Int {
        try directoryEntry(at: offset, base: base) { nameValue, _ in
            nameValue & 0x8000_0000 == 0 && nameValue == identifier
        }
    }

    private func firstDirectoryEntry(at offset: Int, base: Int) throws -> Int {
        try directoryEntry(at: offset, base: base) { _, _ in true }
    }

    private func directoryEntry(
        at offset: Int,
        base: Int,
        matching predicate: (UInt32, UInt32) -> Bool
    ) throws -> Int {
        guard let named = uint16(at: offset + 12), let ids = uint16(at: offset + 14) else {
            throw FirstDLLAnalysisError.invalidAITXTResource
        }
        let count = Int(named) + Int(ids)
        for index in 0 ..< count {
            let entry = offset + 16 + index * 8
            guard let name = uint32(at: entry), let target = uint32(at: entry + 4) else {
                throw FirstDLLAnalysisError.invalidAITXTResource
            }
            if predicate(name, target) {
                guard target & 0x8000_0000 != 0 else {
                    // The language level points to IMAGE_RESOURCE_DATA_ENTRY.
                    return base + Int(target)
                }
                return base + Int(target & 0x7FFF_FFFF)
            }
        }
        throw FirstDLLAnalysisError.missingAITXTResource
    }

    private func resourceName(at offset: Int) -> String? {
        guard let length = uint16(at: offset) else { return nil }
        var units: [UInt16] = []
        units.reserveCapacity(Int(length))
        for index in 0 ..< Int(length) {
            guard let unit = uint16(at: offset + 2 + index * 2) else { return nil }
            units.append(unit)
        }
        return String(decoding: units, as: UTF16.self)
    }

    private func sections(at offset: Int, count: Int) throws -> [PESection] {
        try (0 ..< count).map { index in
            let header = offset + index * 40
            guard let virtualSize = uint32(at: header + 8),
                  let virtualAddress = uint32(at: header + 12),
                  let rawSize = uint32(at: header + 16),
                  let rawOffset = uint32(at: header + 20)
            else {
                throw FirstDLLAnalysisError.invalidAITXTResource
            }
            return PESection(
                virtualAddress: virtualAddress,
                size: max(virtualSize, rawSize),
                rawOffset: rawOffset
            )
        }
    }

    private func fileOffset(forRVA rva: UInt32, sections: [PESection]) -> Int? {
        guard let section = sections.first(where: {
            rva >= $0.virtualAddress && UInt64(rva) < UInt64($0.virtualAddress) + UInt64($0.size)
        }) else { return nil }
        return Int(section.rawOffset + (rva - section.virtualAddress))
    }

    private func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }
}

private struct PESection {
    let virtualAddress: UInt32
    let size: UInt32
    let rawOffset: UInt32
}

private struct OriginalMT19937 {
    private static let count = 624
    private var state: [UInt32] = Array(repeating: 0, count: count)
    private var index = count

    init(seed: UInt32) {
        state[0] = seed & 0x7FFF_FFFF
        for index in 1 ..< Self.count {
            state[index] = state[index - 1] &* 69069
        }
    }

    mutating func next(in range: UInt32) -> Int64 {
        let scaled = Double(nextUInt32()) / 4_294_967_296.0 * Double(range - 1)
        return Int64(scaled.rounded(.toNearestOrEven))
    }

    private mutating func nextUInt32() -> UInt32 {
        if index >= Self.count {
            twist()
        }
        var value = state[index]
        index += 1
        value ^= value >> 11
        value ^= (value << 7) & 0x9D2C_5680
        value ^= (value << 15) & 0xEFC6_0000
        value ^= value >> 18
        return value
    }

    private mutating func twist() {
        for index in 0 ..< 227 {
            twist(index, source: index + 397, next: index + 1)
        }
        for index in 227 ..< 623 {
            twist(index, source: index - 227, next: index + 1)
        }
        twist(623, source: 396, next: 0)
        index = 0
    }

    private mutating func twist(_ target: Int, source: Int, next: Int) {
        let joined = (state[target] & 0x8000_0000) | (state[next] & 0x7FFF_FFFF)
        state[target] = state[source] ^ (joined >> 1) ^ (joined & 1 == 0 ? 0 : 0x9908_B0DF)
    }
}
