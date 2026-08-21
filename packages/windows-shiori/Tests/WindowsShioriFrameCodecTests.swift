import Foundation
import Testing
@testable import UtataneWindowsShiori

@Test func `frames use a little endian 32 bit payload length`() throws {
    let frame = try WindowsShioriFrameCodec.encode(Data([0x41, 0x42, 0x43]))
    #expect(Array(frame) == [3, 0, 0, 0, 0x41, 0x42, 0x43])
}

@Test func `ready frame permits zero only when requested`() throws {
    let ready = Data([0, 0, 0, 0])
    #expect(try WindowsShioriFrameCodec.decodeLength(ready, allowsReadyFrame: true) == 0)
    #expect(throws: WindowsShioriProcessError.invalidFrameLength(0)) {
        try WindowsShioriFrameCodec.decodeLength(ready)
    }
}

@Test func `converts a mac path to the Wine Z drive`() {
    let url = URL(filePath: "/Users/test/Ghosts/first.dll")
    #expect(WindowsShioriProcessSession.windowsPath(for: url) == "Z:\\Users\\test\\Ghosts\\first.dll")
}

@Test func `maps Materia kero local surfaces to shell surface IDs`() {
    let script = #"\0\s0さくら\1\s0うにゅう\s[3]\0\s4さくら"#
    #expect(
        MateriaFirstPersonalityEngine.normalizeLegacyKeroSurfaces(in: script)
            == #"\0\s0さくら\1\s[10]うにゅう\s[13]\0\s4さくら"#
    )
}

@Test func `uses clicked kero scope when a Materia response omits its speaker`() {
    #expect(
        MateriaFirstPersonalityEngine.normalizeLegacyKeroSurfaces(
            in: #"\s3うにゅう"#,
            initialScope: 1
        ) == #"\s[13]うにゅう"#
    )
}

@Test func `tracks explicit Materia p scope before mapping a surface`() {
    #expect(
        MateriaFirstPersonalityEngine.normalizeLegacyKeroSurfaces(in: #"\p[1]\s3うにゅう"#)
            == #"\p[1]\s[13]うにゅう"#
    )
}

@Test func `parses repeated UTF8 HEADLINE values and URL extension`() throws {
    let response = Data("""
    HEADLINE/2.0 200 OK\r
    Charset: UTF-8\r
    Headline: 一件目\u{1}https://example.test/1\r
    Headline: 二件目\r
    \r
    """.utf8)
    #expect(try WindowsHeadlineSensor.items(from: response) == [
        WindowsHeadlineItem(title: "一件目", url: "https://example.test/1"),
        WindowsHeadlineItem(title: "二件目")
    ])
}
