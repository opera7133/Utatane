import Foundation
import Testing
@testable import UtataneNetwork

@Test func `mail headers unfold encoded words and retain unknown or malformed encodings`() {
    let header = MailHeaderParser.parse(lines: [
        "From: =?UTF-8?B?5aSq6YOO?= <taro@example.invalid>",
        "Subject: =?UTF-8?Q?hello_?=", "\t=?UTF-8?Q?world_=E6=97=A5=E6=9C=AC?=", "", "Subject: ignored body"
    ])
    #expect(header.sender == "太郎 <taro@example.invalid>")
    #expect(header.subject == "hello world 日本")
    #expect(MailHeaderParser.decodeWords("plain text") == "plain text")
    for malformed in ["=?unknown?B?YWJj?=", "=?utf-8?Q?=ZZ?=", "=?utf-8?B?***?="] {
        #expect(MailHeaderParser.decodeWords(malformed) == malformed)
    }
    #expect(MailHeaderParser.decodeWords("=?UTF-8?Q?a?= and =?UTF-8?Q?b?=") == "a and b")
}

@Test func `mail headers decode Japanese legacy charsets and missing fields`() throws {
    for (name, encoding) in [("Shift_JIS", String.Encoding.shiftJIS), ("ISO-2022-JP", .iso2022JP)] {
        let bytes = try #require("日本の件名".data(using: encoding))
        #expect(MailHeaderParser.decodeWords("=?\(name)?B?\(bytes.base64EncodedString())?=") == "日本の件名")
    }
    let missing = MailHeaderParser.parse(lines: ["Date: anything"])
    #expect(missing.sender.isEmpty && missing.subject.isEmpty)
    #expect(MailHeaderParser.parse(lines: ["sUbJeCt: test"]).subject == "test")
}
