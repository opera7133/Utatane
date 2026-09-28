import Foundation
import Testing
@testable import UtataneCore

@Test(arguments: [(5, YayaDLLVersionDetector.MajorVersion.five), (6, .six)])
func `reads YAYA major version from PE FileVersion`(major: Int, expected: YayaDLLVersionDetector.MajorVersion) {
    #expect(YayaDLLVersionDetector.detect(in: makeVersionResourceDLL(major: major)) == expected)
}

@Test func `does not guess a version from arbitrary bytes`() {
    #expect(YayaDLLVersionDetector.detect(in: Data("yaya.dll Tc603-2".utf8)) == .unknown)
}

private func makeVersionResourceDLL(major: Int) -> Data {
    var data = Data(repeating: 0, count: 0x400)
    func put16(_ offset: Int, _ value: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    func put32(_ offset: Int, _ value: Int) {
        put16(offset, value)
        put16(offset + 2, value >> 16)
    }
    put16(0, 0x5A4D)
    put32(0x3C, 0x80)
    put32(0x80, 0x0000_4550)
    put16(0x86, 1) // section count
    put16(0x94, 224) // optional header size
    put16(0x98, 0x10B) // PE32
    put32(0x108, 0x1000) // resource directory RVA
    put32(0x10C, 0x200)
    put32(0x180, 0x200) // section virtual size
    put32(0x184, 0x1000) // section RVA
    put32(0x188, 0x200) // raw size
    put32(0x18C, 0x200) // raw offset
    put16(0x20E, 1) // one type entry
    put32(0x210, 16) // VERSIONINFO
    put32(0x214, 0x8000_0018)
    put16(0x226, 1) // one name entry
    put32(0x228, 1)
    put32(0x22C, 0x8000_0030)
    put16(0x23E, 1) // one language entry
    put32(0x240, 1041)
    put32(0x244, 0x48)
    put32(0x248, 0x1060) // resource data RVA
    put32(0x24C, 92)
    put16(0x260, 92) // VS_VERSION_INFO block length
    put16(0x262, 52) // VS_FIXEDFILEINFO length
    for (index, unit) in "VS_VERSION_INFO".utf16.enumerated() {
        put16(0x266 + index * 2, Int(unit))
    }
    put32(0x288, 0xFEEF_04BD)
    put32(0x28C, 0x0001_0000)
    put32(0x290, major << 16)
    put32(0x298, 5 << 16) // ProductVersion is still 5 in YAYA 6
    return data
}
