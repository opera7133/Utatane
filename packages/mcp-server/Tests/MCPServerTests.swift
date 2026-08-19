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
        "get_active_ghost_list", "get_expression_table", "SakuraScript"
    ])
}
