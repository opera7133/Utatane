import Foundation
import Testing
@testable import UtataneCore

@Test
func `resolves built in and registered properties case insensitively`() async throws {
    let date = Date(timeIntervalSince1970: 1_735_732_923.456)
    let properties = PropertySystem(
        configuration: .init(
            basewareName: "Utatane",
            basewareVersion: "1.2.3",
            values: ["currentghost.name": "Emily"]
        ),
        now: { date }
    )

    #expect(try await properties.value(for: "BASEWARE.NAME") == "Utatane")
    #expect(try await properties.value(for: "currentghost.name") == "Emily")
    #expect(await properties.values(for: ["baseware.version", "missing"]) == ["1.2.3", ""])
}

@Test
func `only writes explicitly writable properties`() async throws {
    let properties = PropertySystem(configuration: .init(
        basewareName: "Utatane",
        basewareVersion: "1",
        values: ["currentghost.shelllist(master).menu": ""],
        writableProperties: ["currentghost.shelllist(master).menu"]
    ))

    try await properties.setValue("hidden", for: "CURRENTGHOST.SHELLLIST(master).MENU")
    #expect(try await properties.value(for: "currentghost.shelllist(master).menu") == "hidden")
    await #expect(throws: PropertySystemError.readOnlyProperty("baseware.name")) {
        try await properties.setValue("Elsewhere", for: "baseware.name")
    }
}
