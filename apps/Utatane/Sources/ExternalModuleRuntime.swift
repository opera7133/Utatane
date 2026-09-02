import Foundation
import UtataneCore
import UtataneNativeSaori
import UtatanePlugin
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori
import UtataneWindowsShiori

enum ExternalModuleRuntimeError: LocalizedError {
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(statusCode):
            "外部モジュールの要求に失敗しました: \(statusCode)"
        }
    }
}

actor FallbackPersonalityEngine: PersonalityEngine {
    private let primary: any PersonalityEngine
    private let fallback: any PersonalityEngine

    init(primary: any PersonalityEngine, fallback: any PersonalityEngine) {
        self.primary = primary
        self.fallback = fallback
    }

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let response = try await primary.response(for: event)
        if response.script != nil || !response.references.isEmpty {
            return response
        }
        return try await fallback.response(for: event)
    }

    func shutdown() async {
        await primary.shutdown()
        await fallback.shutdown()
    }
}

actor ExternalSHIORIPersonalityEngine: PersonalityEngine {
    enum Backend: Sendable {
        case dynamicLibrary(DynamicLibraryModuleSession)
        case windowsDLL(WindowsDLLModuleProcessSession)

        func request(_ message: String) throws -> String {
            switch self {
            case let .dynamicLibrary(session): try session.request(message)
            case let .windowsDLL(session): try session.request(message)
            }
        }

        var charset: String {
            switch self {
            case .dynamicLibrary: "UTF-8"
            case let .windowsDLL(session): session.charset
            }
        }
    }

    private let backend: Backend
    private let adapter = GhostEventShioriAdapter()

    init(backend: Backend) {
        self.backend = backend
    }

    func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext(charset: backend.charset)
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        } else if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }
        let request = adapter.request(for: event, context: context)
        var response = try ShioriMessageParser.parseResponse(backend.request(request.serialized()))
        if Shiori2Compatibility.shouldRetry(response),
           let legacyRequest = Shiori2Compatibility.eventRequest(from: request)
        {
            response = try ShioriMessageParser.parseResponse(backend.request(legacyRequest.serialized()))
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ExternalModuleRuntimeError.requestFailed(response.statusCode)
        }
        let script = response.scriptValue.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }
}

final class ExternalSaoriModuleSession: ExternalSaoriModule, @unchecked Sendable {
    enum Backend: Sendable {
        case dynamicLibrary(DynamicLibraryModuleSession)
        case windowsDLL(WindowsDLLModuleProcessSession)

        func request(_ message: String) throws -> String {
            switch self {
            case let .dynamicLibrary(session): try session.request(message)
            case let .windowsDLL(session): try session.request(message)
            }
        }

        var charset: String {
            switch self {
            case .dynamicLibrary: "UTF-8"
            case .windowsDLL: "Shift_JIS"
            }
        }
    }

    private let backend: Backend

    init(backend: Backend) {
        self.backend = backend
    }

    func call(arguments: [String]) -> String {
        var lines = [
            "EXECUTE SAORI/1.0",
            "Charset: \(backend.charset)",
            "Sender: Utatane",
            "SecurityLevel: local"
        ]
        lines += arguments.enumerated().map { "Argument\($0.offset): \($0.element)" }
        guard let rawResponse = try? backend.request(lines.joined(separator: "\r\n") + "\r\n\r\n"),
              let response = try? ShioriMessageParser.parseResponse(rawResponse),
              (200 ..< 300).contains(response.statusCode)
        else { return "" }

        var values = [response.headers["Result"] ?? ""]
        var index = 0
        while let value = response.headers["Value\(index)"] {
            values.append(value)
            index += 1
        }
        return values.joined(separator: "\u{1}")
    }
}
