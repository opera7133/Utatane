import Foundation
import Testing
@testable import UtataneCore

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
