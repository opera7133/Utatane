import Foundation
import Testing
@testable import UtataneCore

@Test
func `decodes and encodes declared EUC JP through the portable fallback`() throws {
    let bytes = Data([
        0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74, 0x2C, 0x45, 0x55, 0x43, 0x2D,
        0x4A, 0x50, 0x0A, 0x6E, 0x61, 0x6D, 0x65, 0x2C, 0xA4, 0xA6, 0xA4, 0xBF,
        0xA4, 0xBF, 0xA4, 0xCD, 0x0A
    ])

    let decoded = try #require(LegacyTextDecoder.decode(bytes))

    #expect(decoded == "charset,EUC-JP\nname,うたたね\n")
    #expect(LegacyTextDecoder.encode(decoded, charset: "EUC-JP") == bytes)
}

@Test func `decodes a declared Korean charset`() throws {
    let encoding = try #require(LegacyTextDecoder.encoding(named: "EUC-KR"))
    let data = try #require("charset,EUC-KR\nname,니세사쿠라\n".data(using: encoding))

    #expect(LegacyTextDecoder.decode(data)?.contains("name,니세사쿠라") == true)
}

@Test func `decodes legacy files that mix Korean and Japanese lines`() throws {
    let korean = try #require(LegacyTextDecoder.encoding(named: "EUC-KR"))
    let shiftJIS = try #require(LegacyTextDecoder.encoding(named: "Shift_JIS"))
    var data = try #require("charset,EUC-KR\ncraftmanw,세루리안\n".data(using: korean))
    try data.append(#require("sakura.name,さくら\n".data(using: shiftJIS)))

    let decoded = try #require(LegacyTextDecoder.decode(data))
    #expect(decoded.contains("craftmanw,세루리안"))
    #expect(decoded.contains("sakura.name,さくら"))
}
