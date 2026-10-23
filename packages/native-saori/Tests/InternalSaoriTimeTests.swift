import Foundation
import Testing
import UtataneCore
@testable import UtataneNativeSaori

private func time(_ function: String, _ arguments: String...) throws -> String {
    try InternalSaoriTime.execute(function, arguments: arguments, now: Date(timeIntervalSince1970: 1_791_720_000))
}

@Test func `internal time formats published examples offsets and strict dates`() throws {
    #expect(try time("Format", "0", "%Y/%m/%d %H:%M (%a)", "--tz=+09:00") == "1970/01/01 09:00 (Thu)")
    #expect(try time("Format", "20261011T210000+0900", "", "--tz=UTC") == "2026-10-11T12:00:00Z")
    #expect(try time("Format", "2026-10-11 21:00", "http", "--tz=Asia/Tokyo") == "Sun, 11 Oct 2026 12:00:00 GMT")
    #expect(try time("Format", "Sun, 11 Oct 2026 12:00:00 GMT", "epoch", "--tz=UTC") == "1791720000")
    #expect(try time("Format", "2026-10-11T12:00:00.999Z", "epochms", "--tz=UTC") == "1791720000000")
    #expect(try time("Format", "now", "epoch", "--tz=UTC") == "1791720000")
    #expect(try time("Format", "-1", "%Y-%m-%d %H:%M:%S %j %u %w %z %:z %%", "--tz=UTC") == "1969-12-31 23:59:59 365 3 3 +0000 +00:00 %")
    #expect(try time("Format", "0").contains("1970"))
    for input in ["2026-02-30", "2026-01-01T25:00Z", "2026-01-01T00:00:60Z", "1600-01-01", "Mon, 11 Oct 2026 12:00:00 GMT", "garbage"] {
        #expect(throws: InternalSaoriTime.Failure.self) { try time("Format", input, "epoch", "--tz=UTC") }
    }
    for zone in ["+18:01", "+19", "+09:60", "Unknown/Zone", "Tokyo Standard Time"] {
        #expect(throws: InternalSaoriTime.Failure.self) { try time("Format", "0", "epoch", "--tz=\(zone)") }
    }
    for pattern in ["garbage", "%Q", "%", "%:q"] {
        #expect(throws: InternalSaoriTime.Failure.self) { try time("Format", "0", pattern) }
    }
}

@Test func `internal time uses calendar addition and truncates signed differences`() throws {
    let leap = try time("Add", "2024-01-31T12:00Z", "1", "month", "--tz=UTC")
    #expect(try time("Format", leap, "", "--tz=UTC") == "2024-02-29T12:00:00Z")
    #expect(try time("Diff", "2024-01-31T12:00Z", "2024-02-29T12:00Z", "month", "--tz=UTC") == "1")
    #expect(try time("Diff", "2026-12-20T10:00", "2026-12-24", "day", "--tz=UTC") == "3")
    #expect(try time("Diff", "2026-12-24", "2026-12-20T10:00", "days", "--tz=UTC") == "-3")
    #expect(try time("Diff", "0", "-119", "minute", "--tz=UTC") == "-1")
    let dst = try time("Add", "2026-03-07T12:00", "1", "day", "--tz=America/New_York")
    #expect(try time("Format", dst, "", "--tz=America/New_York") == "2026-03-08T12:00:00-04:00")
    #expect(try time("Diff", "2026-03-07T12:00", dst, "hour", "--tz=America/New_York") == "23")
    #expect(try time("Diff", "2026-03-07T12:00", dst, "day", "--tz=America/New_York") == "1")
    #expect(throws: InternalSaoriTime.Failure.self) { try time("Format", "2026-03-08T02:30", "epoch", "--tz=America/New_York") }
}

@Test func `internal time enforces epoch and arithmetic bounds`() throws {
    #expect(try time("Format", "-62135596800", "epoch", "--tz=UTC") == "-62135596800")
    #expect(try time("Format", "-62135596800", "", "--tz=UTC") == "0001-01-01T00:00:00Z")
    #expect(try time("Format", "253402300799", "epochms", "--tz=UTC") == "253402300799000")
    for arguments in [["-62135596801", "epoch", "--tz=UTC"], ["253402300800", "epoch", "--tz=UTC"], [String(Int64.max), "epoch", "--tz=UTC"]] {
        #expect(throws: InternalSaoriTime.Failure.self) { try InternalSaoriTime.execute("Format", arguments: arguments, now: Date()) }
    }
    let cutover = try time("Add", "-12220243200", "1", "day", "--tz=UTC")
    #expect(try time("Format", cutover, "", "--tz=UTC") == "1582-10-05T00:00:00Z")
    #expect(try time("Diff", "-12220243200", cutover, "day", "--tz=UTC") == "1")
    let secondYear = try time("Add", "-62135596800", "1", "year", "--tz=UTC")
    #expect(try time("Format", secondYear, "", "--tz=UTC") == "0002-01-01T00:00:00Z")
    #expect(throws: InternalSaoriTime.Failure.self) { try time("Add", "253402300799", "1", "second", "--tz=UTC") }
    #expect(throws: InternalSaoriTime.Failure.self) { try time("Add", "0", String(Int64.max), "year", "--tz=UTC") }
    #expect(throws: InternalSaoriTime.Failure.self) { try time("Add", "0", String(Int64.max), "hour", "--tz=UTC") }
}

@Test func `internal SAORI probes preserve empty positions and reject header injection`() {
    #expect(InternalSaoriProbe.run(module: "internal_time", arguments: ["Format", "0", "", "--tz=UTC"]).response.contains("Result: 1970-01-01T00:00:00Z"))
    #expect(InternalSaoriProbe.run(module: "internal_time", arguments: ["Format", "0"]).response.contains("SAORI/1.0 200"))
    #expect(InternalSaoriProbe.run(module: "internal_time", arguments: ["Format", "0", "", "--async=probe"]).response.contains("ghost required"))
    #expect(InternalSaoriProbe.run(module: "internal_time\r\nInjected: yes", arguments: []).response.contains("400"))
    #expect(InternalSaoriProbe.run(module: "internal_text", arguments: ["Normalize", "NFC", "bad\ntext"]).response.contains("400"))
}

@Test func `internal SAORI diagnostic summaries omit secrets and payloads`() {
    let secret = "sensitive-key-12345"
    let request = Data("EXECUTE SAORI/1.0\r\nModule: internal_crypto\r\nArgument0: HMAC\r\nArgument1: sha256\r\nArgument2: \(secret)\r\nArgument3: private text\r\n\r\n".utf8)
    let response = Data("SAORI/1.0 200 OK\r\nResult: secret-output\r\n\r\n".utf8)
    let summary = InternalSaoriDiagnostics.summary(request: request, response: response, started: DispatchTime.now().uptimeNanoseconds, session: UUID(), completion: true)
    #expect(summary.contains("module=internal_crypto function=HMAC status=200"))
    #expect(summary.contains("phase=complete"))
    for forbidden in [secret, "private text", "secret-output", "Argument", "Result:"] {
        #expect(!summary.contains(forbidden))
    }
}

@Test func `internal SAORI call recording is opt in and bounded by the log store`() {
    let store = AppLogStore(maxEntries: 1)
    let diagnostics = InternalSaoriDiagnostics(store: store)
    let request = Data("EXECUTE SAORI/1.0\r\nModule: internal_data\r\nArgument0: Convert\r\nArgument1: secret\r\n\r\n".utf8)
    let response = Data("SAORI/1.0 400 Bad Request\r\nErrorDescription: secret\r\n\r\n".utf8)
    func record() {
        diagnostics.record(request: request, response: response, started: DispatchTime.now().uptimeNanoseconds, session: UUID())
    }
    record()
    #expect(store.snapshot().isEmpty)
    diagnostics.isEnabled = true
    record(); record()
    let entries = store.snapshot()
    #expect(entries.count == 1)
    #expect(entries.first?.category == "InternalSAORI")
    #expect(entries.first?.message.contains("status=400") == true)
    #expect(entries.first?.message.contains("secret") == false)
    diagnostics.isEnabled = false
    let before = store.snapshot()
    record()
    #expect(store.snapshot() == before)
}
