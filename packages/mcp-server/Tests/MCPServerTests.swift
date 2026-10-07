import Foundation
import Testing
@testable import UtataneMCP

@Test func `initializes and lists SSP compatible tools`() async throws {
    let server = MCPServer(client: UtataneBridgeClient())
    let initialized = try #require(await server.handle([
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": ["protocolVersion": "2025-06-18"]
    ]))
    let result = try #require(initialized["result"] as? [String: Any])
    #expect(result["protocolVersion"] as? String == "2025-06-18")

    let listed = try #require(await server.handle([
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/list"
    ]))
    let listResult = try #require(listed["result"] as? [String: Any])
    let tools = try #require(listResult["tools"] as? [[String: Any]])
    #expect(Set(tools.compactMap { $0["name"] as? String }) == [
        "get_active_ghost_list", "get_expression_table", "SakuraScript", "get_status", "get_log", "raise_event", "reload", "dump_surface", "dump_balloon"
    ])
}

@Test func `MCP event arguments round trip through encoded payload without header injection`() async throws {
    let client = UtataneBridgeClient(send: { request in
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("Command: RaiseEvent\r\n"))
        let encoded = try #require(body.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("Payload: ") }))
        let data = try #require(Data(base64Encoded: String(encoded.dropFirst(9))))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["references"] as? [String] == ["a\r\nCommand: Reload", "日本語"])
        #expect(!body.contains("\r\nCommand: Reload"))
        return (Data("SSTP/1.4 200 OK\r\nScript: {\"event\":\"OnTest\"}\r\n\r\n".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    let server = MCPServer(client: client)
    let response = try #require(await server.handle(["id": 1, "method": "tools/call", "params": ["name": "raise_event", "arguments": ["event": "OnTest", "references": ["a\r\nCommand: Reload", "日本語"]]]]))
    #expect(response["error"] == nil)
    let invalid = try #require(await server.handle(["id": 2, "method": "tools/call", "params": ["name": "dump_surface", "arguments": [:]]]))
    #expect(invalid["error"] != nil)
}
