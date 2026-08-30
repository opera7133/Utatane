import Foundation
import UtataneCore
import UtataneRuntime
import UtataneSakuraScript
import UtataneShiori

public actor NativeNiseShioriPersonalityEngine: PersonalityEngine {
    private let adapter = GhostEventShioriAdapter()
    private let stateStoreURL: URL
    private var evaluator: NiseEvaluator

    public init(masterDirectoryURL: URL, stateStoreURL: URL? = nil) throws {
        let dictionary = try NiseDictionary.load(from: masterDirectoryURL)
        self.stateStoreURL = stateStoreURL ?? masterDirectoryURL.appending(path: "nise-shiori-state.json")
        let state = (try? Data(contentsOf: self.stateStoreURL)).flatMap { try? JSONDecoder().decode(NisePersistedState.self, from: $0) } ?? .init()
        let description = Self.description(at: masterDirectoryURL)
        evaluator = NiseEvaluator(
            dictionary: dictionary,
            state: state,
            selfName: description["sakura.name"] ?? description["name"] ?? "",
            keroName: description["kero.name"] ?? description["name2"] ?? ""
        )
        for (key, values) in state.learnedWords {
            evaluator.dictionary.words[key, default: []].append(contentsOf: values)
        }
    }

    public static func supports(masterDirectoryURL: URL, shioriFilename: String?) -> Bool {
        guard shioriFilename?.caseInsensitiveCompare("niseshiori.dll") == .orderedSame else { return false }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: masterDirectoryURL.path) else { return false }
        return files.contains { name in
            name.lowercased().hasPrefix("ai") && ["txt", "dtx"].contains(URL(filePath: name).pathExtension.lowercased())
        }
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        try await response(for: event).script
    }

    public func response(for event: GhostEvent) async throws -> PersonalityResponse {
        let request = adapter.request(for: event)
        let value = evaluator.response(for: request)
        try save()
        let references = evaluator.communicateTarget.map { [0: $0] } ?? [:]
        evaluator.communicateTarget = nil
        return PersonalityResponse(
            script: value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) },
            references: references
        )
    }

    public func shutdown() async {
        try? save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: stateStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(evaluator.state).write(to: stateStoreURL, options: .atomic)
    }

    private static func description(at directory: URL) -> [String: String] {
        let url = directory.appending(path: "descript.txt")
        guard let data = try? Data(contentsOf: url), let source = LegacyTextDecoder.decode(data) else { return [:] }
        return source.components(separatedBy: .newlines).reduce(into: [:]) { result, line in
            let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard fields.count == 2 else { return }
            result[fields[0].trimmingCharacters(in: .whitespaces).lowercased()] = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
