import Foundation
import UtataneCore
import UtataneNativeSaori
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public enum NativeYayaPersonalityError: LocalizedError, Equatable, Sendable {
    case unsuccessfulResponse(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .unsuccessfulResponse(statusCode, reason):
            "YAYAがエラーを返した: \(statusCode) \(reason)"
        }
    }
}

public actor NativeYayaPersonalityEngine: PersonalityEngine {
    private let session: NativeYayaSession
    private let adapter: GhostEventShioriAdapter

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        session = try NativeYayaSession(masterDirectoryURL: masterDirectoryURL, saoriRegistry: saoriRegistry)
        adapter = GhostEventShioriAdapter()
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        return ["yaya.txt", "yaya_config.txt"].contains { name in
            fileManager.fileExists(
                atPath: masterDirectoryURL.appending(path: name, directoryHint: .notDirectory).path
            )
        }
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext()
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        } else if case let .mouse(mouseEvent) = event {
            context.scope = mouseEvent.scope
            context.mouseX = mouseEvent.x
            context.mouseY = mouseEvent.y
            context.mouseButton = mouseEvent.button
        }

        let response = try session.request(adapter.request(for: event, context: context))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NativeYayaPersonalityError.unsuccessfulResponse(
                response.statusCode,
                response.reasonPhrase
            )
        }
        let script = response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
        return PersonalityResponse(script: script, references: response.referenceValues)
    }
}
