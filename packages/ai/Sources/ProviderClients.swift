import Foundation

private func request(
    url: URL,
    configuration: AIProviderConfiguration,
    authorization: (String, String)? = nil,
    body: [String: Any]
) throws -> URLRequest {
    if configuration.apiKey.isEmpty, configuration.kind != .openAICompatible {
        throw AIProviderError.missingAPIKey
    }
    var result = URLRequest(url: url, timeoutInterval: configuration.timeoutSeconds)
    result.httpMethod = "POST"
    result.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let authorization {
        result.setValue(authorization.1, forHTTPHeaderField: authorization.0)
    }
    result.httpBody = try JSONSerialization.data(withJSONObject: body)
    return result
}

public struct OpenAIResponsesClient: AIProviderClient {
    let configuration: AIProviderConfiguration
    let session: URLSession

    public func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        let base = configuration.baseURL ?? URL(string: "https://api.openai.com/v1")!
        let inputText = try AIJSON.input(input)
        let messages = history.map { ["role": $0.role.rawValue, "content": $0.content] }
            + [["role": "user", "content": inputText]]
        let body: [String: Any] = [
            "model": configuration.model,
            "instructions": systemPrompt + "\n" + AIJSON.instruction,
            "input": messages,
            "text": ["format": ["type": "json_schema", "name": "ghost_action", "strict": true, "schema": Self.schema]]
        ]
        let value = try await session.aiJSON(request(
            url: base.appending(path: "responses"), configuration: configuration,
            authorization: ("Authorization", "Bearer \(configuration.apiKey)"), body: body
        ))
        guard let output = value["output"] as? [[String: Any]],
              let content = output.compactMap({ $0["content"] as? [[String: Any]] }).flatMap(\.self).first,
              let text = content["text"] as? String else { throw AIProviderError.invalidResponse }
        return try AIJSON.decode(text)
    }

    static var schema: [String: Any] {
        [
            "type": "object", "additionalProperties": false,
            "properties": ["speech": ["anyOf": [
                ["type": "object", "additionalProperties": false, "properties": ["text": ["type": "string"], "surface": ["type": "integer"]], "required": ["text", "surface"]],
                ["type": "null"]
            ]]], "required": ["speech"]
        ]
    }
}

public struct OpenAICompatibleClient: AIProviderClient {
    let configuration: AIProviderConfiguration
    let session: URLSession

    public func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        let base = configuration.baseURL ?? URL(string: "http://127.0.0.1:11434/v1")!
        var messages: [[String: String]] = [["role": "system", "content": systemPrompt + "\n" + AIJSON.instruction]]
        messages += history.map { ["role": $0.role.rawValue, "content": $0.content] }
        try messages.append(["role": "user", "content": AIJSON.input(input)])
        var auth: (String, String)?
        if !configuration.apiKey.isEmpty {
            auth = ("Authorization", "Bearer \(configuration.apiKey)")
        }
        let value = try await session.aiJSON(request(
            url: base.appending(path: "chat/completions"), configuration: configuration,
            authorization: auth, body: ["model": configuration.model, "messages": messages, "temperature": 0.7]
        ))
        guard let choices = value["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let text = message["content"] as? String else { throw AIProviderError.invalidResponse }
        return try AIJSON.decode(text)
    }
}

public struct AnthropicMessagesClient: AIProviderClient {
    let configuration: AIProviderConfiguration
    let session: URLSession

    public func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        let base = configuration.baseURL ?? URL(string: "https://api.anthropic.com/v1")!
        let inputText = try AIJSON.input(input)
        let messages = history.map { ["role": $0.role.rawValue, "content": $0.content] }
            + [["role": "user", "content": inputText]]
        var req = try request(url: base.appending(path: "messages"), configuration: configuration, body: [
            "model": configuration.model, "max_tokens": 500, "system": systemPrompt + "\n" + AIJSON.instruction, "messages": messages
        ])
        req.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let value = try await session.aiJSON(req)
        guard let content = value["content"] as? [[String: Any]], let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else { throw AIProviderError.invalidResponse }
        return try AIJSON.decode(text)
    }
}

public struct GeminiClient: AIProviderClient {
    let configuration: AIProviderConfiguration
    let session: URLSession

    public func respond(systemPrompt: String, history: [AIConversationMessage], input: AIPersonalityInput) async throws -> AIPersonalityOutput {
        let base = configuration.baseURL ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        let url = base.appending(path: "models/\(configuration.model):generateContent")
        var contents: [[String: Any]] = history.map { ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.content]]] }
        try contents.append(["role": "user", "parts": [["text": AIJSON.input(input)]]])
        var req = try request(url: url, configuration: configuration, body: [
            "systemInstruction": ["parts": [["text": systemPrompt + "\n" + AIJSON.instruction]]],
            "contents": contents, "generationConfig": ["responseMimeType": "application/json"]
        ])
        req.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        let value = try await session.aiJSON(req)
        guard let candidates = value["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { throw AIProviderError.invalidResponse }
        return try AIJSON.decode(text)
    }
}
