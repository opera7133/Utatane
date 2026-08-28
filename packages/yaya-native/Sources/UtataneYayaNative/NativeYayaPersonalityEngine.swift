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
    private let usesAyaConfiguration: Bool

    public init(masterDirectoryURL: URL, saoriRegistry: NativeSaoriRegistry? = nil) throws {
        session = try NativeYayaSession(masterDirectoryURL: masterDirectoryURL, saoriRegistry: saoriRegistry)
        adapter = GhostEventShioriAdapter()
        usesAyaConfiguration = Self.usesAyaConfiguration(in: masterDirectoryURL)
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        let fileManager = FileManager.default
        return ["yaya.txt", "yaya_config.txt", "aya5.txt", "aya.txt"].contains { name in
            fileManager.fileExists(
                atPath: masterDirectoryURL.appending(path: name, directoryHint: .notDirectory).path
            )
        }
    }

    private static func usesAyaConfiguration(in directory: URL) -> Bool {
        let files = FileManager.default
        let hasYaya = ["yaya.txt", "yaya_config.txt"].contains { files.fileExists(atPath: directory.appending(path: $0).path) }
        let hasAya = ["aya5.txt", "aya.txt"].contains { files.fileExists(atPath: directory.appending(path: $0).path) }
        return hasAya && !hasYaya
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

        var request = adapter.request(for: event, context: context)
        var response = try session.request(request)
        if usesAyaConfiguration, case .randomTalk = event,
           (200 ..< 300).contains(response.statusCode), response.value?.isEmpty != false
        {
            request.headers = ShioriHeaders(request.headers.entries.map { field in
                field.name.caseInsensitiveCompare("ID") == .orderedSame
                    ? ShioriHeader(name: field.name, value: "OnAiTalk") : field
            })
            response = try session.request(request)
        }
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
