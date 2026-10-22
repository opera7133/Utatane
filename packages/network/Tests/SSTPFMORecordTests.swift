import Foundation
import Testing
@testable import UtataneNetwork

@Test func `FMO encodes distinct ghosts and prevents record injection`() {
    let root = URL(fileURLWithPath: "/tmp/Utatane")
    let ghost = root.appending(path: "Ghosts/さくら")
    let record = SSTPFMORecord(
        ghostDirectory: ghost, basewareDirectory: root,
        name: "さくら\r\nforged.name\u{1}bad", partnerName: "うにゅう", fullName: "テスト",
        surfaces: [0: 7, 1: -1]
    )
    let second = SSTPFMORecord(
        ghostDirectory: root.appending(path: "Other/さくら"), basewareDirectory: root,
        name: "別のさくら", partnerName: "", fullName: "別", surfaces: [:]
    )
    let id = SSTPFMORecord.identifier(for: ghost)
    #expect(id.count == 32)
    #expect(id != SSTPFMORecord.identifier(for: second.ghostDirectory))
    let body = SSTPFMORecord.serialize([record, second])
    #expect(body.contains("\(id).sakura.surface\u{1}7\r\n"))
    #expect(body.contains("\(id).kero.surface\u{1}-1"))
    #expect(body.contains("\(id).name\u{1}さくらforged.namebad\r\n"))
    #expect(body.contains("\(id).ghostpath\u{1}\(ghost.path)/\r\n"))
    #expect(!body.contains(".hwnd"))
    let response = String(decoding: SSTPResponse(additionalData: body).data, as: UTF8.self)
    #expect(response.hasSuffix(body + "\r\n\r\n"))
    #expect(SSTPFMORecord.serialize([]).isEmpty)
}
