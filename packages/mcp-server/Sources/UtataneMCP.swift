import Foundation

@main
struct UtataneMCP {
    static func main() async {
        let server = MCPServer(client: UtataneBridgeClient())
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = await server.handle(request),
                  let output = try? JSONSerialization.data(withJSONObject: response),
                  let text = String(data: output, encoding: .utf8)
            else { continue }
            print(text)
            fflush(stdout)
        }
    }
}

struct MCPServer: Sendable {
    let client: UtataneBridgeClient

    func handle(_ request: [String: Any]) async -> [String: Any]? {
        guard let method = request["method"] as? String else { return nil }
        guard let id = request["id"] else { return nil }
        do {
            let result: [String: Any]
            switch method {
            case "initialize":
                let parameters = request["params"] as? [String: Any]
                result = [
                    "protocolVersion": parameters?["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "utatane-mcp", "version": "0.1.0"]
                ]
            case "tools/list":
                result = ["tools": Self.tools()]
            case "tools/call":
                result = try await callTool(parameters: request["params"] as? [String: Any] ?? [:])
            case "ping":
                result = [:]
            default:
                return error(id: id, code: -32601, message: "Method not found: \(method)")
            }
            return ["jsonrpc": "2.0", "id": id, "result": result]
        } catch {
            return self.error(id: id, code: -32000, message: error.localizedDescription)
        }
    }

    private func callTool(parameters: [String: Any]) async throws -> [String: Any] {
        guard let name = parameters["name"] as? String else { throw MCPError.invalidArguments }
        let arguments = parameters["arguments"] as? [String: Any] ?? [:]
        let text: String
        switch name {
        case "get_active_ghost_list":
            text = try await client.command("GetActiveGhostList")
        case "get_expression_table":
            guard let ghostID = arguments["ghost_id"] as? String, !ghostID.isEmpty else {
                throw MCPError.invalidArguments
            }
            text = try await client.command("GetExpressionTable", ghostID: ghostID)
        case "SakuraScript":
            guard let script = arguments["script"] as? String, !script.isEmpty else {
                throw MCPError.invalidArguments
            }
            _ = try await client.command(
                "SakuraScript",
                ghostID: arguments["ghost_id"] as? String,
                script: script
            )
            text = "SakuraScriptを実行した。"
        default:
            throw MCPError.unknownTool(name)
        }
        return ["content": [["type": "text", "text": text]]]
    }

    private func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func tools() -> [[String: Any]] {
        [
            [
                "name": "get_active_ghost_list",
                "description": "Utataneで現在起動しているゴーストの一覧を取得する。",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]
            ],
            [
                "name": "get_expression_table",
                "description": "指定した起動中ゴーストで利用できるsurfaceと表情エイリアスを取得する。",
                "inputSchema": [
                    "type": "object",
                    "properties": ["ghost_id": ["type": "string", "description": "get_active_ghost_listが返すID"]],
                    "required": ["ghost_id"],
                    "additionalProperties": false
                ]
            ],
            [
                "name": "SakuraScript",
                "description": "起動中のゴーストでSakuraScriptを実行する。ghost_idを省略するとメインゴーストが対象。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "script": ["type": "string", "description": "実行するSakuraScript"],
                        "ghost_id": ["type": "string", "description": "省略可能な対象ゴーストID"]
                    ],
                    "required": ["script"],
                    "additionalProperties": false
                ]
            ]
        ]
    }
}

struct UtataneBridgeClient: Sendable {
    private let endpoint = URL(string: "http://127.0.0.1:9801/api/sstp/v1")!

    func command(_ command: String, ghostID: String? = nil, script: String? = nil) async throws -> String {
        var lines = ["SEND SSTP/1.4", "Charset: UTF-8", "Sender: utatane-mcp", "Command: \(command)"]
        if let ghostID {
            lines.append("Ghost-ID: \(ghostID)")
        }
        if let script {
            lines.append("Script: \(script.replacingOccurrences(of: "\n", with: "\\n"))")
        }
        let body = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let source = String(data: data, encoding: .utf8),
              source.contains("SSTP/1.4 200") || source.contains("SSTP/1.4 204")
        else { throw MCPError.utataneUnavailable }
        return source.split(whereSeparator: \.isNewline).first(where: {
            $0.lowercased().hasPrefix("script:")
        }).map { String($0.dropFirst("script:".count)).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

enum MCPError: LocalizedError {
    case invalidArguments
    case unknownTool(String)
    case utataneUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "引数が不正。"
        case let .unknownTool(name): "未対応のツール: \(name)"
        case .utataneUnavailable: "Utataneへ接続できない。先にUtataneを起動してください。"
        }
    }
}
