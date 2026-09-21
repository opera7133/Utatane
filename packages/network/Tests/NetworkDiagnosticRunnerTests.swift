import Testing
@testable import UtataneNetwork

@Test
func `builds bounded ping arguments with DF and UTF-8 data`() {
    let arguments = NetworkDiagnosticRunner.pingArguments(
        host: "example.com",
        count: 99,
        size: 80000,
        timeoutMilliseconds: 0,
        ttl: 999,
        dontFragment: true,
        data: "あいうえおか"
    )
    #expect(arguments == [
        "-n", "-c", "20", "-s", "18", "-W", "1", "-m", "255", "-D",
        "-p", "e38182e38184e38186e38188e3818ae3", "example.com"
    ])
}
