import Testing
@testable import UtatanePlatformMacOS

@Test
func `network status references follow UKADOC shape`() {
    let snapshot = NetworkStatusSnapshot(
        isOnline: true,
        addresses: ["192.0.2.1", "2001:db8::1"],
        interfaceType: "wifi",
        isExpensive: false
    )
    #expect(snapshot.references == [
        0: "online", 1: "192.0.2.1\u{1}2001:db8::1", 2: "wifi",
        3: "0", 4: "0", 5: "unrestricted"
    ])
}

@Test
func `recycle bin references include deltas`() {
    let previous = RecycleBinSnapshot(itemCount: 3, totalBytes: 100)
    let current = RecycleBinSnapshot(itemCount: 1, totalBytes: 40)
    #expect(current.references(previous: previous) == [
        0: "1", 1: "40", 2: "-2", 3: "-60", 4: "1", 5: ""
    ])
}
