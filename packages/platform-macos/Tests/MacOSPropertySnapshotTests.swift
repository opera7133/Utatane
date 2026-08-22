import Testing
@testable import UtatanePlatformMacOS

@MainActor
@Test
func `provides monitor cursor and theme properties`() {
    let values = MacOSPropertySnapshot.values()

    #expect(Int(values["system.monitor.count"] ?? "") != nil)
    #expect(values["system.cursor.pos"]?.contains(",") == true)
    #expect(["dark", "light"].contains(values["system.theme.os.mode"] ?? ""))
    if (Int(values["system.monitor.count"] ?? "0") ?? 0) > 0 {
        #expect(values["system.monitor.index(0).rect"]?.split(separator: ",").count == 4)
        #expect(values["system.monitor.index(0).primary"] == "1")
    }
}
