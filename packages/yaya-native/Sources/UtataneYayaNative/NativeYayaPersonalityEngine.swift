import Foundation
import UtataneCore
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

    public init(masterDirectoryURL: URL) throws {
        session = try NativeYayaSession(masterDirectoryURL: masterDirectoryURL)
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
        var context = ShioriEventContext()
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        }

        let response = try session.request(adapter.request(for: event, context: context))
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NativeYayaPersonalityError.unsuccessfulResponse(
                response.statusCode,
                response.reasonPhrase
            )
        }
        guard let value = response.value, !value.isEmpty else { return nil }
        return SakuraScript(rawValue: value)
    }
}
