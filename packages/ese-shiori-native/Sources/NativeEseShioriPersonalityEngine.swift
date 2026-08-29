import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public enum NativeEseShioriError: LocalizedError, Sendable {
    case missingConfiguration(URL)
    public var errorDescription: String? {
        if case let .missingConfiguration(url) = self {
            return "ese-shiori設定が見つからない: \(url.path)"
        }; return nil
    }
}

public actor NativeEseShioriPersonalityEngine: PersonalityEngine {
    private struct PersistedState: Codable {
        var variables: [String: String]
        var storage: [Int: String]
    }

    private var evaluator: EseEvaluator
    private let adapter = GhostEventShioriAdapter()
    private let stateStoreURL: URL

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let ini = masterDirectoryURL.appending(path: "eseai.ini")
        guard FileManager.default.fileExists(atPath: ini.path) else { throw NativeEseShioriError.missingConfiguration(ini) }
        let iniText = try LegacyTextDecoder.decode(Data(contentsOf: ini)) ?? ""
        let charset = Self.value(named: "DIC_CHAR_SET", in: iniText) ?? "Shift_JIS"
        let dictionary = try EseDictionary.load(masterDirectoryURL: masterDirectoryURL, charset: charset)
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "ese-shiori-state.json")
        let saved = (try? Data(contentsOf: self.stateStoreURL)).flatMap { try? JSONDecoder().decode(PersistedState.self, from: $0) }
        evaluator = EseEvaluator(
            dictionary: dictionary,
            storage: saved?.storage ?? [:],
            variables: saved?.variables ?? [:]
        )
        evaluator.variables["selfname"] = Self.descriptValue("name", at: masterDirectoryURL) ?? ""
        evaluator.variables["keroname"] = Self.descriptValue("name2", at: masterDirectoryURL) ?? ""
    }

    public static func supports(masterDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: masterDirectoryURL.appending(path: "eseai.ini").path)
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        var context = ShioriEventContext(charset: "UTF-8")
        if case let .mouseClick(scope, _) = event {
            context.scope = scope
        }
        if case let .mouse(mouse) = event {
            context.scope = mouse.scope; context.mouseX = mouse.x; context.mouseY = mouse.y; context.mouseButton = mouse.button
        }
        let request = adapter.request(for: event, context: context)
        if request.id?.caseInsensitiveCompare("OnUserInput") == .orderedSame,
           request.reference(0)?.caseInsensitiveCompare("SetUsername") == .orderedSame,
           let text = request.reference(1)
        {
            evaluator.variables["username"] = text
        }
        let value = evaluator.response(for: request)
        if case .close = event {
            try save()
        }
        return PersonalityResponse(script: value.isEmpty ? nil : SakuraScript(rawValue: value))
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: stateStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(PersistedState(
            variables: evaluator.variables,
            storage: evaluator.storage
        )).write(to: stateStoreURL, options: .atomic)
    }

    private static func value(named name: String, in text: String) -> String? {
        text.components(separatedBy: .newlines).compactMap { line -> String? in
            let parts = line.split(separator: "=", maxSplits: 1); guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame else { return nil }; return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }.first
    }

    private static func descriptValue(_ key: String, at master: URL) -> String? {
        let url = master.appending(path: "descript.txt"); guard let text = try? Data(contentsOf: url), let decoded = LegacyTextDecoder.decode(text) else { return nil }
        return decoded.components(separatedBy: .newlines).first { $0.hasPrefix(key + ",") }.map { String($0.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
