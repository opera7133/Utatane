import Foundation
import Testing
@testable import UtataneNetwork

@Test func `parses SSTP send requests and serializes responses`() throws {
    let request = try SSTPServer.parse(Data("""
    SEND SSTP/1.4\r
    Charset: UTF-8\r
    Sender: Test\r
    Event: OnTest\r
    Reference0: value\r
    \r

    """.utf8))
    #expect(request.method == "SEND")
    #expect(request.value(for: "event") == "OnTest")
    #expect(request.value(for: "Reference0") == "value")

    let response = String(data: SSTPResponse(script: "\\hhello\\e").data, encoding: .utf8)
    #expect(response?.contains("SSTP/1.4 200 OK") == true)
    #expect(response?.contains("Script: \\hhello\\e") == true)
}

@Test func `unwraps and wraps SSTP over HTTP`() throws {
    let sstp = Data("SEND SSTP/1.4\r\nCharset: UTF-8\r\nScript: \\hHTTP test\\e\r\n\r\n".utf8)
    let http = Data("POST /api/sstp/v1 HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: \(sstp.count)\r\nOrigin: http://localhost:3000\r\n\r\n".utf8) + sstp
    #expect(try SSTPServer.parseHTTPRequest(http) == sstp)

    let response = String(data: SSTPServer.httpResponse(for: SSTPResponse(script: "\\hOK\\e")), encoding: .utf8)
    #expect(response?.hasPrefix("HTTP/1.1 200 OK\r\n") == true)
    #expect(response?.contains("Content-Type: text/plain") == true)
    #expect(response?.contains("SSTP/1.4 200 OK") == true)
}

@Test func `rejects nonlocal browser origins for SSTP over HTTP`() {
    let sstp = Data("SEND SSTP/1.4\r\nCharset: UTF-8\r\n\r\n".utf8)
    let http = Data("POST /api/sstp/v1 HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: \(sstp.count)\r\nOrigin: https://example.com\r\n\r\n".utf8) + sstp
    #expect(throws: SSTPError.self) {
        try SSTPServer.parseHTTPRequest(http)
    }
}
