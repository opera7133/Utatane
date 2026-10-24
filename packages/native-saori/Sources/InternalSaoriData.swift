import Foundation
import UtataneCore
import zlib

/// Byte formats are independent of the charset of the SAORI wire message.
enum InternalSaoriData {
    typealias Failure = InternalSaoriService.Failure

    static func charset(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.lowercased().filter { $0 != "-" && $0 != "_" }
        guard !normalized.hasPrefix("utf16"), !normalized.hasPrefix("utf32"),
              LegacyTextDecoder.encoding(named: name) != nil else { throw Failure("invalid parameter") }
        return ["shiftjis", "sjis", "windows31j"].contains(normalized) ? "CP932" : name
    }

    static func decode(_ text: String, as encoding: String, charset: String = "UTF-8") throws -> Data {
        let bytes = Array(text.utf8)
        guard bytes.count <= InternalSaoriService.maximumBytes else { throw Failure("too large") }
        switch encoding.lowercased() {
        case "text":
            guard let data = try LegacyTextDecoder.encode(text, charset: self.charset(charset)) else { throw Failure("invalid encoding") }
            return data
        case "hex":
            guard bytes.count.isMultiple(of: 2), bytes.allSatisfy({ hex($0) != nil }) else { throw Failure("invalid encoding") }
            return Data(stride(from: 0, to: bytes.count, by: 2).map { hex(bytes[$0])! * 16 + hex(bytes[$0 + 1])! })
        case "base64", "base64url":
            let source = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            let unpadded = String(source.prefix { $0 != "=" })
            let padding = source.count - unpadded.count
            guard unpadded.utf8.allSatisfy({ (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 43 || $0 == 47 }),
                  source.dropFirst(unpadded.count).allSatisfy({ $0 == "=" }), unpadded.count % 4 != 1,
                  padding == 0 || (padding <= 2 && source.count.isMultiple(of: 4))
            else { throw Failure("invalid encoding") }
            let padded = unpadded + String(repeating: "=", count: (4 - unpadded.count % 4) % 4)
            guard let data = Data(base64Encoded: padded) else { throw Failure("invalid encoding") }
            return data
        case "url":
            var result = Data()
            var index = 0
            while index < bytes.count {
                if bytes[index] == 37 {
                    guard index + 2 < bytes.count, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else { throw Failure("invalid encoding") }
                    result.append(high * 16 + low); index += 3
                } else {
                    result.append(bytes[index]); index += 1
                }
            }
            return result
        case "base32":
            guard bytes.allSatisfy({ $0 < 128 }) else { throw Failure("invalid encoding") }
            let text = text.uppercased()
            let source = Array(text.prefix { $0 != "=" }.utf8)
            let padding = text.utf8.count - source.count
            let expected = [0: 0, 2: 6, 4: 4, 5: 3, 7: 1]
            guard let required = expected[source.count % 8],
                  text.dropFirst(source.count).allSatisfy({ $0 == "=" }), padding == 0 || padding == required else { throw Failure("invalid encoding") }
            return try unpack(source.map { byte in
                guard let index = base32.firstIndex(of: byte) else { throw Failure("invalid encoding") }
                return UInt8(index)
            })
        case "bech32":
            guard text == text.lowercased() || text == text.uppercased(),
                  let separator = bytes.lastIndex(of: 49), (1 ... 83).contains(separator), bytes.count >= separator + 7,
                  bytes.prefix(separator).allSatisfy({ (33 ... 126).contains($0) }) else { throw Failure("invalid encoding") }
            let lower = Array(text.lowercased().utf8)
            let hrp = Array(lower.prefix(separator))
            let values = try lower.dropFirst(separator + 1).map { byte -> UInt8 in
                guard let index = bech32.firstIndex(of: byte) else { throw Failure("invalid encoding") }
                return UInt8(index)
            }
            guard checksum(expand(hrp) + values) == 1 else { throw Failure("invalid encoding") }
            return try unpack(Array(values.dropLast(6)))
        default: throw Failure("unsupported algorithm")
        }
    }

    static func format(_ data: Data, as encoding: String, charset: String = "UTF-8", hrp: String? = nil) throws -> String {
        guard data.count <= InternalSaoriService.maximumBytes else { throw Failure("too large") }
        if encoding == "HEX" {
            return data.map { String(format: "%02X", $0) }.joined()
        }
        switch encoding.lowercased() {
        case "text":
            guard let text = try LegacyTextDecoder.decode(data, strictlyUsing: self.charset(charset)),
                  !text.utf8.contains(0), !text.utf8.contains(13), !text.utf8.contains(10) else { throw Failure("not text", status: 500) }
            return text
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        case "base64": return data.base64EncodedString()
        case "base64url": return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        case "url": return data.map { byte in
                (65 ... 90).contains(byte) || (97 ... 122).contains(byte) || (48 ... 57).contains(byte) || [45, 46, 95, 126].contains(byte)
                    ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
            }.joined()
        case "base32":
            let values = pack(data)
            return String(decoding: values.map { base32[Int($0)] }, as: UTF8.self) + String(repeating: "=", count: (8 - values.count % 8) % 8)
        case "bech32":
            guard let hrp, (1 ... 83).contains(hrp.utf8.count), hrp.utf8.allSatisfy({ (33 ... 126).contains($0) }),
                  hrp == hrp.lowercased() || hrp == hrp.uppercased() else { throw Failure("invalid parameter") }
            let prefix = hrp.lowercased()
            let values = pack(data)
            let sum = checksum(expand(Array(prefix.utf8)) + values + Array(repeating: 0, count: 6)) ^ 1
            let check = (0 ..< 6).map { UInt8((sum >> (5 * (5 - $0))) & 31) }
            return prefix + "1" + String(decoding: (values + check).map { bech32[Int($0)] }, as: UTF8.self)
        default: throw Failure("unsupported algorithm")
        }
    }

    static func compress(_ data: Data, algorithm: String, level: Int = -1, decompress: Bool = false) throws -> Data {
        let bits: Int32
        switch algorithm.lowercased() {
        case "gzip": bits = 31
        case "zlib": bits = 15
        case "deflate": bits = -15
        default: throw Failure("unsupported algorithm")
        }
        var stream = z_stream()
        let initialized = decompress
            ? inflateInit2_(&stream, bits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            : deflateInit2_(&stream, Int32(level), Z_DEFLATED, bits, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else { throw Failure("internal error", status: 500) }
        defer {
            if decompress {
                inflateEnd(&stream)
            } else {
                deflateEnd(&stream)
            }
        }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            var result = Data()
            var chunk = [UInt8](repeating: 0, count: 32768)
            while true {
                let previousInput = stream.avail_in
                let status = chunk.withUnsafeMutableBytes { output in
                    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(output.count)
                    return decompress ? inflate(&stream, Z_NO_FLUSH) : deflate(&stream, Z_FINISH)
                }
                let written = chunk.count - Int(stream.avail_out)
                guard written <= InternalSaoriService.maximumBytes - result.count else { throw Failure("too large") }
                result.append(contentsOf: chunk.prefix(written))
                if status == Z_STREAM_END {
                    if decompress, stream.avail_in > 0 {
                        guard bits == 31, inflateReset2(&stream, bits) == Z_OK else { throw Failure("invalid encoding") }
                        continue // Concatenated gzip members; cumulative output limit remains in force.
                    }
                    return result
                }
                guard status == Z_OK, written > 0 || stream.avail_in < previousInput else {
                    throw Failure(decompress ? "invalid encoding" : "internal error", status: decompress ? 400 : 500)
                }
            }
        }
    }

    private static let base32 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
    private static let bech32 = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l".utf8)
    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48 ... 57: byte - 48
        case 65 ... 70: byte - 55
        case 97 ... 102: byte - 87
        default: nil
        }
    }

    private static func pack(_ data: Data) -> [UInt8] {
        var accumulator: UInt32 = 0, count = 0
        var result: [UInt8] = []
        for byte in data {
            accumulator = (accumulator << 8) | UInt32(byte); count += 8
            while count >= 5 {
                count -= 5; result.append(UInt8((accumulator >> count) & 31))
            }
        }
        if count > 0 {
            result.append(UInt8((accumulator << (5 - count)) & 31))
        }
        return result
    }

    private static func unpack(_ values: [UInt8]) throws -> Data {
        var accumulator: UInt32 = 0, count = 0
        var result = Data()
        for value in values {
            accumulator = (accumulator << 5) | UInt32(value); count += 5
            if count >= 8 {
                count -= 8; result.append(UInt8((accumulator >> count) & 255))
            }
        }
        guard count < 5, (accumulator & ((1 << count) - 1)) == 0 else { throw Failure("invalid encoding") }
        return result
    }

    private static func expand(_ hrp: [UInt8]) -> [UInt8] {
        hrp.map { $0 >> 5 } + [0] + hrp.map { $0 & 31 }
    }

    private static func checksum(_ values: [UInt8]) -> UInt32 {
        var sum: UInt32 = 1
        let generators: [UInt32] = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]
        for value in values {
            let high = sum >> 25
            sum = ((sum & 0x1FFFFFF) << 5) ^ UInt32(value)
            for index in 0 ..< 5 where (high >> index) & 1 != 0 {
                sum ^= generators[index]
            }
        }
        return sum
    }
}
