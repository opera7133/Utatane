import Foundation
import Testing
import UtataneCore
@testable import UtataneNativeSaori

private func internalResponse(_ module: String, _ arguments: [String], method: String = "EXECUTE", charset: String = "UTF-8") throws -> String {
    let wire = (["\(method) SAORI/1.0", "Charset: \(charset)", "Module: \(module)"] + arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }).joined(separator: "\r\n") + "\r\n\r\n"
    let data = try #require(LegacyTextDecoder.encode(wire, charset: charset))
    return try #require(LegacyTextDecoder.decode(InternalSaoriService().response(to: data), preferredCharset: charset))
}

@Test func `internal SAORI lists only callable modules and negotiates failures`() throws {
    let modules = try internalResponse("INTERNAL_SYSTEM", ["ListModules"])
    #expect(modules.contains("Value0: internal_crypto\r\n"))
    #expect(modules.contains("internal_time"))
    let functions = try internalResponse("internal_system", ["ListFunctions", "internal_random"])
    #expect(functions.contains("Result: Bytes,Number,UUID\r\n"))
    #expect(try internalResponse("internal_unknown", [], method: "GET Version").contains("ErrorDescription: unknown module"))
    #expect(try internalResponse("internal_random", [], method: "GET Version").hasPrefix("SAORI/1.0 200"))
    #expect(try internalResponse("internal_text", ["Unknown"]).contains("ErrorDescription: unknown function"))
}

@Test func `internal text preserves Unicode and empty arguments in both wire encodings`() throws {
    #expect(try internalResponse("internal_text", ["Normalize", "NFKC", "ｶﾞｲﾄﾞ①"]).contains("Result: ガイド1\r\n"))
    // Swift string equality is canonically equivalent; assert the wire's actual scalars too.
    let normalized = try internalResponse("internal_text", ["Normalize", "NFKC", "ｶﾞｲﾄﾞ①"])
    let line = try #require(normalized.components(separatedBy: "\r\n").first { $0.hasPrefix("Result: ") })
    #expect(line.dropFirst(8).unicodeScalars.map(\.value) == [0x30AC, 0x30A4, 0x30C9, 0x31])
    #expect(try internalResponse("internal_text", ["Normalize", "NFC", "e\u{301}"]).contains("Result: é\r\n"))
    #expect(try internalResponse("internal_text", ["Normalize", "NFD", "é"]).contains("Result: e\u{301}\r\n"))
    #expect(try internalResponse("internal_text", ["Normalize", "NFKD", "①"]).contains("Result: 1\r\n"))
    #expect(try internalResponse("internal_text", ["Normalize", "NFKC", "ｶﾞｲﾄﾞ"], charset: "Shift_JIS").contains("Result: ガイド\r\n"))
    #expect(try internalResponse("internal_text", ["Normalize", "NFC", ""]).hasPrefix("SAORI/1.0 204"))
    #expect(try internalResponse("internal_text", ["Normalize", "NFC"]).contains("ErrorDescription: invalid parameter"))
}

@Test func `internal crypto uses published digest and HMAC vectors`() throws {
    #expect(try internalResponse("internal_crypto", ["Digest", "sha256", "abc"]).contains("Result: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\r\n"))
    #expect(try internalResponse("internal_crypto", ["HMAC", "sha256", String(repeating: "0b", count: 20), "Hi There", "--key-in=hex"]).contains("Result: b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7\r\n"))
    #expect(try internalResponse("internal_crypto", ["Digest", "sha3", "abc"]).contains("unsupported algorithm"))
    #expect(try internalResponse("internal_crypto", ["Digest", "sha256", "abc", "--data-in=file"]).contains("unsupported algorithm"))
}

@Test func `internal data converts strictly without accepting malformed bytes`() throws {
    #expect(try internalResponse("internal_data", ["Convert", "48656c6c6f", "--data-in=hex", "--out=base64"]).contains("Result: SGVsbG8=\r\n"))
    #expect(try internalResponse("internal_data", ["Convert", "_w", "--in=base64url", "--out=hex"]).contains("Result: ff\r\n"))
    #expect(try internalResponse("internal_data", ["Convert", "ff", "--in=hex"]).contains("not text"))
    #expect(try internalResponse("internal_data", ["Convert", "aaZ0", "--in=hex"]).contains("invalid encoding"))
    #expect(try internalResponse("internal_data", ["Convert", "a", "--in=hex"]).contains("invalid encoding"))
    #expect(try internalResponse("internal_data", ["Convert", "0a", "--in=hex"]).contains("not text"))
    #expect(try internalResponse("internal_data", ["Convert", "--literal", "--out=hex"]).contains("Result: 2d2d6c69746572616c\r\n"))
}

@Test func `internal random handles inclusive Int64 ranges UUID variants and bounds`() throws {
    #expect(try internalResponse("internal_random", ["Number", String(Int64.min), String(Int64.min)]).contains("Result: \(Int64.min)\r\n"))
    #expect(try internalResponse("internal_random", ["Number", String(Int64.min), String(Int64.max)]).hasPrefix("SAORI/1.0 200"))
    #expect(try internalResponse("internal_random", ["Number", "1", "0"]).contains("invalid parameter"))
    #expect(try internalResponse("internal_random", ["Bytes", "0"]).contains("out of range"))
    #expect(try internalResponse("internal_random", ["Bytes", "1025"]).contains("out of range"))
    for version in ["4", "7"] {
        let response = try internalResponse("internal_random", ["UUID", "--version=\(version)"])
        let line = try #require(response.components(separatedBy: "\r\n").first { $0.hasPrefix("Result: ") })
        let uuid = String(line.dropFirst(8))
        #expect(UUID(uuidString: uuid) != nil)
        #expect(Array(uuid)[14] == Character(version))
        #expect("89ab".contains(Array(uuid)[19]))
    }
    let bytes = try internalResponse("internal_random", ["Bytes", "1024"])
    let line = try #require(bytes.components(separatedBy: "\r\n").first { $0.hasPrefix("Result: ") })
    #expect(line.dropFirst(8).count == 2048)
}

@Test func `internal SAORI rejects duplicate headers sparse arguments and unknown options`() throws {
    for headers in [
        "Module: internal_text\r\nModule: internal_random\r\n",
        "Module: internal_text\r\nArgument0: Normalize\r\nArgument2: NFKC\r\n",
        "Module: internal_text\r\nArgument0: Normalize\r\nArgument1: NFC\r\nArgument2: hello\nInjected: true\r\n"
    ] {
        let data = Data(("EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\n" + headers + "\r\n").utf8)
        #expect(String(decoding: InternalSaoriService().response(to: data), as: UTF8.self).hasPrefix("SAORI/1.0 400"))
    }
    #expect(try internalResponse("internal_random", ["UUID", "--bad=1"]).contains("invalid parameter"))
    #expect(try internalResponse("internal_random", ["UUID", "--version=4", "--version=7"]).contains("-7"))
}

@Test func `data codec follows published vectors and separates data charset from wire`() throws {
    #expect(try internalResponse("internal_data", ["Convert", "こんにちは", "--charset=Shift_JIS", "--out=HEX"]).contains("Result: 82B182F182C982BF82CD"))
    #expect(try internalResponse("internal_data", ["Convert", "a4a2", "--data-in=hex", "--charset=EUC-JP"]).contains("Result: あ"))
    #expect(try internalResponse("internal_data", ["Convert", "a", "--charset=UTF-16"]).contains("invalid parameter"))
    #expect(try internalResponse("internal_crypto", ["Digest", "SHA-256", "abc", "--out=HEX"]).contains("BA7816BF"))
    #expect(try internalResponse("internal_data", ["Convert", "0a", "--data-in=hex"]).hasPrefix("SAORI/1.0 500"))
    #expect(try internalResponse("internal_data", ["Convert", "ff", "--data-in=hex", "--out=base64", "--OUT=HEX"]).contains("Result: FF"))
    for encoded in ["/w==", "_w==", "/w", "_w"] {
        for format in ["base64", "base64url"] {
            #expect(try InternalSaoriData.decode(encoded, as: format) == Data([255]))
        }
    }
    for encoded in ["a", "AA=", "AA===", "A=A=", "AA==x", "AA ", "\nAA=="] {
        #expect(throws: (any Error).self) { try InternalSaoriData.decode(encoded, as: "base64") }
    }
    #expect(try InternalSaoriData.decode("%E3%81%82+%25", as: "url") == Data("あ+%".utf8))
    #expect(try InternalSaoriData.format(Data("あ+%".utf8), as: "url") == "%E3%81%82%2B%25")
    for invalid in ["%", "%0", "%GG"] {
        #expect(throws: (any Error).self) { try InternalSaoriData.decode(invalid, as: "url") }
    }
    // RFC 4648 base32 test vectors.
    for (plain, encoded) in [("", ""), ("f", "MY======"), ("fo", "MZXQ===="), ("foo", "MZXW6==="), ("foob", "MZXW6YQ="), ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI======")] {
        #expect(try InternalSaoriData.format(Data(plain.utf8), as: "base32") == encoded)
        #expect(try InternalSaoriData.decode(encoded.lowercased(), as: "base32") == Data(plain.utf8))
        #expect(try InternalSaoriData.decode(encoded.replacingOccurrences(of: "=", with: ""), as: "base32") == Data(plain.utf8))
    }
    for invalid in ["M", "MZ======", "MY=====", "MY======X", "M1======"] {
        #expect(throws: (any Error).self) { try InternalSaoriData.decode(invalid, as: "base32") }
    }
    let bytes = try InternalSaoriData.decode("7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e", as: "hex")
    let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
    #expect(try InternalSaoriData.format(bytes, as: "bech32", hrp: "npub") == npub)
    #expect(try InternalSaoriData.decode(npub.uppercased(), as: "bech32") == bytes)
    for invalid in [npub + "x", "N" + npub.dropFirst(), String(npub.dropLast()) + "q"] {
        #expect(throws: (any Error).self) { try InternalSaoriData.decode(invalid, as: "bech32") }
    }
}

@Test func `compression interoperates with external gzip zlib and raw deflate vectors`() throws {
    // Python zlib/gzip encodings of Hello; these do not depend on our encoder.
    let vectors = ["gzip": "H4sIAAAAAAAACvNIzcnJBwCCidH3BQAAAA==", "zlib": "eJzzSM3JyQcABYwB9Q==", "deflate": "80jNyckHAA=="]
    for (algorithm, encoded) in vectors {
        let input = try #require(Data(base64Encoded: encoded))
        #expect(try InternalSaoriData.compress(input, algorithm: algorithm, decompress: true) == Data("Hello".utf8))
        for bad in [Data(input.dropLast()), input + Data([0]), Data([0, 0, 0])] {
            #expect(throws: (any Error).self) { try InternalSaoriData.compress(bad, algorithm: algorithm, decompress: true) }
        }
        for level in [0, 1, 9] {
            for data in [Data(), Data("日本語".utf8), Data((0 ... 255).map(UInt8.init))] {
                let compressed = try InternalSaoriData.compress(data, algorithm: algorithm, level: level)
                #expect(try InternalSaoriData.compress(compressed, algorithm: algorithm, decompress: true) == data)
            }
        }
    }
    let gzipText = try #require(vectors["gzip"])
    let gzip = try #require(Data(base64Encoded: gzipText))
    #expect(try InternalSaoriData.compress(gzip + gzip, algorithm: "gzip", decompress: true) == Data("HelloHello".utf8))
    var corrupt = gzip; corrupt[corrupt.count - 8] ^= 1
    #expect(throws: (any Error).self) { try InternalSaoriData.compress(corrupt, algorithm: "gzip", decompress: true) }
    #expect(try internalResponse("internal_data", ["Decompress", "gzip", #require(vectors["gzip"])]).contains("Result: Hello"))
    #expect(try internalResponse("internal_data", ["Compress", "gzip", "Hello", "--level=10"]).contains("invalid parameter"))
}

@Test func `decompression applies one cumulative limit across gzip members`() throws {
    let half = Data(repeating: 65, count: InternalSaoriService.maximumBytes / 2)
    let member = try InternalSaoriData.compress(half, algorithm: "gzip")
    #expect(try InternalSaoriData.compress(member + member, algorithm: "gzip", decompress: true).count == InternalSaoriService.maximumBytes)
    #expect(throws: (any Error).self) { try InternalSaoriData.compress(member + member + member, algorithm: "gzip", decompress: true) }
}
