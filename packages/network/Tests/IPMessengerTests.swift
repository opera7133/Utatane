import Foundation
import Testing
@testable import UtataneNetwork

@Test
func `IP Messenger entry round trips legacy and UTF8 identity fields`() throws {
    let packet = IPMessengerPacket(
        packetNumber: 1_700_000_000,
        userName: "利用者",
        hostName: "端末.local",
        command: IPMessengerProtocol.broadcastEntry | IPMessengerProtocol.utf8CapabilityOption,
        additional: "うたたね",
        groupName: "伺か"
    )

    let data = try IPMessengerProtocol.encode(packet)
    let decoded = try IPMessengerProtocol.decode(data)

    #expect(decoded == packet)
    #expect(data.contains(0))
    #expect(data.range(of: Data("NN:うたたね".utf8)) != nil)
}

@Test
func `IP Messenger message uses UTF8 when the option is set`() throws {
    let packet = IPMessengerPacket(
        packetNumber: 42,
        userName: "user",
        hostName: "mac.local",
        command: IPMessengerProtocol.sendMessage
            | IPMessengerProtocol.sendCheckOption
            | IPMessengerProtocol.utf8Option,
        additional: "こんにちは\n二行目"
    )

    let data = try IPMessengerProtocol.encode(packet)

    #expect(String(data: data, encoding: .utf8) == "1:42:user:mac.local:8388896:こんにちは\n二行目")
    #expect(try IPMessengerProtocol.decode(data) == packet)
}

@Test
func `IP Messenger decodes legacy Shift JIS messages`() throws {
    let source = "1:99:legacy:old-mac:32:従来形式"
    let data = try #require(source.data(using: .shiftJIS))

    let packet = try IPMessengerProtocol.decode(data)

    #expect(packet.packetNumber == 99)
    #expect(packet.mode == IPMessengerProtocol.sendMessage)
    #expect(packet.additional == "従来形式")
}

@Test
func `IP Messenger entry metadata overrides lossy legacy fields`() throws {
    var data = Data("1:7:user:host:16777217:nickname".utf8)
    data.append(0)
    data.append(Data("group".utf8))
    data.append(0)
    data.append(Data("\nUN:利用者\nHN:端末.local\nNN:表示名\nGN:日本語組\n".utf8))

    let packet = try IPMessengerProtocol.decode(data)

    #expect(packet.userName == "利用者")
    #expect(packet.hostName == "端末.local")
    #expect(packet.additional == "表示名")
    #expect(packet.groupName == "日本語組")
}

@Test
func `IP Messenger message preserves the discovered peer identity`() {
    let existing = IPMessengerPeer(
        address: "192.0.2.1",
        port: 2425,
        userName: "user",
        hostName: "mac.local",
        displayName: "表示名",
        groupName: "グループ",
        supportsUTF8: false
    )
    let message = IPMessengerPacket(
        packetNumber: 8,
        userName: "user",
        hostName: "mac.local",
        command: IPMessengerProtocol.sendMessage | IPMessengerProtocol.utf8Option,
        additional: "これは本文"
    )

    let peer = IPMessengerService.makePeer(
        from: message,
        address: existing.address,
        port: existing.port,
        existing: existing,
        usesEntryIdentity: false
    )

    #expect(peer.displayName == "表示名")
    #expect(peer.groupName == "グループ")
    #expect(peer.supportsUTF8)
}

@Test
func `IP Messenger sends UTF8 only to peers that advertise support`() {
    let legacy = IPMessengerPeer(
        address: "192.0.2.1",
        port: 2425,
        userName: "user",
        hostName: "old.local",
        displayName: "Old",
        groupName: "",
        supportsUTF8: false
    )
    let modern = IPMessengerPeer(
        address: "192.0.2.2",
        port: 2425,
        userName: "user",
        hostName: "new.local",
        displayName: "New",
        groupName: "",
        supportsUTF8: true
    )

    #expect(IPMessengerService.messageOptions(for: legacy) == IPMessengerProtocol.sendCheckOption)
    #expect(IPMessengerService.messageOptions(for: modern) == (
        IPMessengerProtocol.sendCheckOption | IPMessengerProtocol.utf8Option
    ))
}

@Test
func `IP Messenger rejects malformed and oversized datagrams`() {
    #expect(throws: IPMessengerError.invalidPacket) {
        try IPMessengerProtocol.decode(Data("not-a-packet".utf8))
    }
    #expect(throws: IPMessengerError.messageTooLarge) {
        try IPMessengerProtocol.decode(Data(
            repeating: 0,
            count: IPMessengerProtocol.maximumDatagramBytes + 1
        ))
    }
}
