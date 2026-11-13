import Foundation

/// Reads the leading metadata blocks without decoding the audio stream.
struct EmbeddedAudioMetadata: Sendable {
    var tags: [String: String] = [:]
    var artwork: Data?
    private var hasFrontCover = false
    private static let readLimit = 16 * 1024 * 1024

    static func read(_ url: URL) -> Self {
        var result = Self()
        guard let file = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? file.close() }
        guard let signature = try? file.read(upToCount: 12) else { return result }

        switch signature.prefix(4) {
        case Data("RIFF".utf8):
            result.readRIFF(file, header: signature)
        case Data("fLaC".utf8), Data("OggS".utf8):
            try? file.seek(toOffset: 0)
            guard let data = try? file.read(upToCount: readLimit) else { return result }
            if signature.starts(with: Data("fLaC".utf8)) {
                result.readFLAC(Array(data))
            } else {
                result.readOgg(Array(data))
            }
        default:
            if signature.starts(with: Data("ID3".utf8)), signature.count >= 10 {
                let header = Array(signature)
                if let length = number(header[6 ..< 10], syncsafe: true), length <= readLimit {
                    try? file.seek(toOffset: 10)
                    if let data = try? file.read(upToCount: length), data.count == length {
                        result.readID3(Array(data), version: Int(header[3]), flags: header[5])
                    }
                }
            }
            if signature.starts(with: Data("ID3".utf8)) || url.pathExtension.lowercased() == "mp3",
               let end = try? file.seekToEnd(), end >= 128,
               (try? file.seek(toOffset: end - 128)) != nil,
               let tail = try? file.read(upToCount: 128), tail.count == 128,
               tail.starts(with: Data("TAG".utf8))
            {
                result.readID3v1(Array(tail))
            }
        }
        return result
    }

    private mutating func store(_ key: String, _ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)), !value.isEmpty else { return }
        if let old = tags[key] {
            if !old.components(separatedBy: "; ").contains(value) {
                tags[key] = old + "; " + value
            }
        } else {
            tags[key] = value
        }
    }

    private mutating func cover(_ data: ArraySlice<UInt8>, type: Int) {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
              artwork == nil || (type == 3 && !hasFrontCover) else { return }
        artwork = Data(data)
        hasFrontCover = type == 3
    }

    private static func number(_ data: ArraySlice<UInt8>, syncsafe: Bool = false, littleEndian: Bool = false) -> Int? {
        guard data.count <= 4, !syncsafe || data.allSatisfy({ $0 < 128 }) else { return nil }
        let shift = syncsafe ? 7 : 8
        return littleEndian ? data.reversed().reduce(0) { ($0 << shift) | Int($1) }
            : data.reduce(0) { ($0 << shift) | Int($1) }
    }

    private static func text(_ data: ArraySlice<UInt8>, encoding: UInt8 = 0) -> String? {
        let bytes = Data(data)
        switch encoding {
        case 0:
            return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .shiftJIS)
                ?? String(data: bytes, encoding: .isoLatin1)
        case 1: return String(data: bytes, encoding: .utf16)
        case 2: return String(data: bytes, encoding: .utf16BigEndian)
        case 3: return String(data: bytes, encoding: .utf8)
        default: return nil
        }
    }

    private static func deunsync(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var previous: UInt8 = 0
        return bytes.filter { byte in
            defer { previous = byte }
            return byte != 0 || previous != 255
        }
    }

    private mutating func readID3(_ raw: [UInt8], version: Int, flags: UInt8) {
        guard (2 ... 4).contains(version), version != 2 || flags & 0x40 == 0 else { return }
        let bytes = version < 4 && flags & 0x80 != 0 ? Self.deunsync(raw[...]) : raw
        var cursor = 0
        if version >= 3, flags & 0x40 != 0 {
            guard bytes.count >= 4, let length = Self.number(bytes[0 ..< 4], syncsafe: version == 4), length >= (version == 4 ? 4 : 0) else { return }
            cursor = length + (version == 3 ? 4 : 0)
        }
        let headerLength = version == 2 ? 6 : 10
        let nameLength = version == 2 ? 3 : 4
        let names = ["TIT2": "title", "TT2": "title", "TPE1": "artist", "TP1": "artist",
                     "TPE2": "albumartist", "TP2": "albumartist", "TALB": "album", "TAL": "album",
                     "TCON": "genre", "TCO": "genre", "TYER": "year", "TYE": "year", "TDRC": "year",
                     "TRCK": "track", "TRK": "track"]
        while cursor + headerLength <= bytes.count, bytes[cursor] != 0 {
            let name = String(decoding: bytes[cursor ..< cursor + nameLength], as: UTF8.self)
            let sizeStart = cursor + nameLength
            let sizeEnd = sizeStart + (version == 2 ? 3 : 4)
            guard let size = Self.number(bytes[sizeStart ..< sizeEnd], syncsafe: version == 4),
                  size > 0, size <= bytes.count - cursor - headerLength else { break }
            let format = version == 2 ? 0 : bytes[cursor + 9]
            cursor += headerLength
            var body = bytes[cursor ..< cursor + size]
            cursor += size
            if version == 3, format & 0xE0 != 0 {
                continue
            }
            if version == 4 {
                if format & 0x4C != 0 {
                    continue
                }
                if format & 1 != 0 {
                    guard body.count >= 4 else { continue }
                    body = body.dropFirst(4)
                }
                if format & 2 != 0 || flags & 0x80 != 0 {
                    body = Self.deunsync(body)[...]
                }
            }
            guard let encoding = body.first else { continue }
            if let key = names[name] {
                store(key, Self.text(body.dropFirst(), encoding: encoding)?.replacingOccurrences(of: "\0", with: "; ").trimmingCharacters(in: CharacterSet(charactersIn: "; ")))
            } else if name == "APIC" || name == "PIC" {
                let data = body.dropFirst()
                let picture = name == "PIC" ? data.dropFirst(3) : data.drop(while: { $0 != 0 }).dropFirst()
                guard let type = picture.first else { continue }
                cover(Self.afterTerminator(picture.dropFirst(), encoding: encoding), type: Int(type))
            } else if name == "COMM" || name == "COM" {
                store("comment", Self.text(Self.afterTerminator(body.dropFirst(4), encoding: encoding), encoding: encoding))
            }
        }
    }

    private static func afterTerminator(_ bytes: ArraySlice<UInt8>, encoding: UInt8) -> ArraySlice<UInt8> {
        let width = encoding == 1 || encoding == 2 ? 2 : 1
        var index = bytes.startIndex
        while index + width <= bytes.endIndex {
            if bytes[index ..< index + width].allSatisfy({ $0 == 0 }) {
                return bytes[(index + width)...]
            }
            index += width
        }
        return bytes.suffix(0)
    }

    private mutating func readID3v1(_ bytes: [UInt8]) {
        for (key, start, end) in [("title", 3, 33), ("artist", 33, 63), ("album", 63, 93),
                                  ("year", 93, 97), ("comment", 97, bytes[125] == 0 ? 125 : 127)] where tags[key] == nil
        {
            store(key, Self.text(bytes[start ..< end].prefix { $0 != 0 }))
        }
        if tags["track"] == nil, bytes[125] == 0, bytes[126] > 0 {
            tags["track"] = String(bytes[126])
        }
    }

    private mutating func readFLAC(_ bytes: [UInt8]) {
        var cursor = 4
        while cursor + 4 <= bytes.count {
            let type = bytes[cursor]
            let length = Self.number(bytes[cursor + 1 ..< cursor + 4]) ?? 0
            cursor += 4
            guard length <= bytes.count - cursor else { return }
            let body = bytes[cursor ..< cursor + length]
            switch type & 127 {
            case 4: readComments(body)
            case 6: readPicture(body)
            default: break
            }
            cursor += length
            if type & 128 != 0 {
                break
            }
        }
    }

    private mutating func readComments(_ bytes: ArraySlice<UInt8>) {
        var cursor = bytes.startIndex
        func length() -> Int? {
            guard cursor + 4 <= bytes.endIndex else { return nil }
            defer { cursor += 4 }
            return Self.number(bytes[cursor ..< cursor + 4], littleEndian: true)
        }
        guard let vendor = length(), vendor <= bytes.endIndex - cursor else { return }
        cursor += vendor
        guard let count = length(), count <= 65536 else { return }
        let names = ["TITLE": "title", "ARTIST": "artist", "ALBUMARTIST": "albumartist", "ALBUM": "album",
                     "GENRE": "genre", "COMMENT": "comment", "DESCRIPTION": "comment", "DATE": "year", "TRACKNUMBER": "track"]
        for _ in 0 ..< count {
            guard let length = length(), length <= bytes.endIndex - cursor else { return }
            let field = String(decoding: bytes[cursor ..< cursor + length], as: UTF8.self)
            cursor += length
            guard let separator = field.firstIndex(of: "=") else { continue }
            let name = field[..<separator].uppercased()
            let value = String(field[field.index(after: separator)...])
            if let key = names[name] {
                store(key, value)
            } else if name == "METADATA_BLOCK_PICTURE", let data = Data(base64Encoded: value) {
                readPicture(Array(data)[...])
            }
        }
    }

    private mutating func readPicture(_ bytes: ArraySlice<UInt8>) {
        var cursor = bytes.startIndex
        func read() -> Int? {
            guard cursor + 4 <= bytes.endIndex else { return nil }
            defer { cursor += 4 }
            return Self.number(bytes[cursor ..< cursor + 4])
        }
        guard let type = read(), let mimeLength = read(), mimeLength <= bytes.endIndex - cursor else { return }
        cursor += mimeLength
        guard let descriptionLength = read(), descriptionLength <= bytes.endIndex - cursor else { return }
        cursor += descriptionLength
        guard bytes.endIndex - cursor >= 16 else { return }
        cursor += 16
        guard let size = read(), size <= bytes.endIndex - cursor else { return }
        cover(bytes[cursor ..< cursor + size], type: type)
    }

    private mutating func readOgg(_ bytes: [UInt8]) {
        var cursor = 0
        var serial: ArraySlice<UInt8>?
        var packet: [UInt8] = []
        var packets = 0
        while cursor + 27 <= bytes.count, packets < 3 {
            guard bytes[cursor ..< cursor + 4].elementsEqual("OggS".utf8) else { return }
            let stream = bytes[cursor + 14 ..< cursor + 18]
            if serial == nil {
                serial = stream
            }
            let segments = Int(bytes[cursor + 26])
            let table = cursor + 27
            guard table + segments <= bytes.count else { return }
            var dataStart = table + segments
            for size in bytes[table ..< dataStart] {
                let end = dataStart + Int(size)
                guard end <= bytes.count else { return }
                if stream == serial {
                    packet.append(contentsOf: bytes[dataStart ..< end])
                    if size < 255 {
                        packets += 1
                        if packet.starts(with: "OpusTags".utf8) {
                            readComments(packet.dropFirst(8))
                            return
                        }
                        if packet.first == 3, packet.dropFirst().starts(with: "vorbis".utf8) {
                            readComments(packet.dropFirst(7))
                            return
                        }
                        packet.removeAll(keepingCapacity: true)
                    }
                }
                dataStart = end
            }
            cursor = dataStart
        }
    }

    private mutating func readRIFF(_ file: FileHandle, header: Data) {
        guard header.count == 12, header.suffix(4).elementsEqual("WAVE".utf8) || header.suffix(4).elementsEqual("AVI ".utf8),
              let end = try? file.seekToEnd() else { return }
        let names = ["INAM": "title", "IART": "artist", "IPRD": "album", "IGNR": "genre", "ICMT": "comment",
                     "ICRD": "year", "ITRK": "track"]
        var cursor: UInt64 = 12
        var remaining = Self.readLimit
        for _ in 0 ..< 65536 {
            guard cursor <= end, end - cursor >= 8,
                  (try? file.seek(toOffset: cursor)) != nil,
                  let header = try? file.read(upToCount: 8), header.count == 8 else { break }
            let chunk = Array(header)
            let name = String(decoding: chunk.prefix(4), as: UTF8.self)
            let length = Self.number(chunk[4 ..< 8], littleEndian: true) ?? 0
            cursor += 8
            guard UInt64(length) <= end - cursor else { break }
            cursor += UInt64(length + length % 2)
            guard name == "LIST" || name.lowercased() == "id3 ", length >= 4, length <= remaining,
                  let data = try? file.read(upToCount: length), data.count == length else { continue }
            remaining -= length
            let bytes = Array(data)
            if name == "LIST", bytes.prefix(4).elementsEqual("INFO".utf8) {
                var entry = 4
                while entry + 8 <= bytes.count {
                    let key = String(decoding: bytes[entry ..< entry + 4], as: UTF8.self)
                    let size = Self.number(bytes[entry + 4 ..< entry + 8], littleEndian: true) ?? 0
                    entry += 8
                    guard size <= bytes.count - entry else { break }
                    if let field = names[key] {
                        store(field, Self.text(bytes[entry ..< entry + size].prefix { $0 != 0 }))
                    }
                    entry += size + size % 2
                }
            } else if name.lowercased() == "id3 ", length >= 10, bytes.prefix(3).elementsEqual("ID3".utf8),
                      let size = Self.number(bytes[6 ..< 10], syncsafe: true), size <= length - 10
            {
                readID3(Array(bytes[10 ..< 10 + size]), version: Int(bytes[3]), flags: bytes[5])
            }
        }
    }
}
