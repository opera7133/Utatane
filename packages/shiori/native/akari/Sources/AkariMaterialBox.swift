import Compression
import Foundation

enum AkariMaterialBox {
    struct Entry: Sendable {
        let path: String
        let data: Data
    }

    static func decode(_ data: Data) -> [Entry]? {
        var reader = Reader(data: data)
        guard reader.uint16() == 1,
              reader.nullTerminatedString(maximumBytes: 64) == "AZ-MaterialBox"
        else { return nil }
        var entries: [Entry] = []
        while !reader.isAtEnd, entries.count < 1024 {
            guard let pathLength = reader.uint16(), (1 ... 4096).contains(pathLength),
                  let pathData = reader.data(count: pathLength),
                  let path = String(data: pathData.dropLast(pathData.last == 0 ? 1 : 0), encoding: .utf8),
                  let compressedLength = reader.uint32(), compressedLength <= 16_777_216,
                  let compressed = reader.data(count: compressedLength),
                  let expanded = inflateZlib(compressed, maximumBytes: 16_777_216)
            else { return nil }
            entries.append(.init(path: path, data: expanded.last == 0 ? Data(expanded.dropLast()) : expanded))
        }
        return reader.isAtEnd && !entries.isEmpty ? entries : nil
    }

    private static func inflateZlib(_ data: Data, maximumBytes: Int) -> Data? {
        guard data.count >= 6, data[0] & 0x0F == 8 else { return nil }
        let payload = data.dropFirst(2).dropLast(4)
        var capacity = 1024
        while capacity <= maximumBytes {
            var output = [UInt8](repeating: 0, count: capacity)
            let count = payload.withUnsafeBytes { source in
                compression_decode_buffer(
                    &output,
                    output.count,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            if count > 0 {
                let result = Data(output.prefix(count))
                return adler32(result) == data.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } ? result : nil
            }
            capacity *= 2
        }
        return nil
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

private struct Reader {
    let data: Data
    var offset = 0
    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func uint16() -> Int? {
        guard let bytes = data(count: 2) else { return nil }
        return Int(bytes[bytes.startIndex]) | Int(bytes[bytes.index(after: bytes.startIndex)]) << 8
    }

    mutating func uint32() -> Int? {
        guard let bytes = data(count: 4) else { return nil }
        return bytes.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
    }

    mutating func data(count: Int) -> Data? {
        guard count >= 0, offset <= data.count - count else { return nil }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }

    mutating func nullTerminatedString(maximumBytes: Int) -> String? {
        let start = offset
        while offset < data.count, offset - start <= maximumBytes {
            if data[offset] == 0 {
                defer { offset += 1 }
                return String(data: data.subdata(in: start ..< offset), encoding: .ascii)
            }
            offset += 1
        }
        return nil
    }
}
