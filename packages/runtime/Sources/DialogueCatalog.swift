import Foundation
import UtataneCore
import UtataneSakuraScript

public struct DialogueCatalog: Codable, Sendable, Equatable {
    public let boot: [String]
    public let close: [String]
    public let randomTalk: [String]
    public let mouseClick: [String: [String]]
    public let choices: [String: [String]]

    public init(
        boot: [String] = [],
        close: [String] = [],
        randomTalk: [String] = [],
        mouseClick: [String: [String]] = [:],
        choices: [String: [String]] = [:]
    ) {
        self.boot = boot
        self.close = close
        self.randomTalk = randomTalk
        self.mouseClick = mouseClick
        self.choices = choices
    }

    public func scripts(for event: GhostEvent) -> [String] {
        switch event {
        case .boot:
            boot
        case .close:
            close
        case .randomTalk:
            randomTalk
        case let .mouseClick(region):
            if let region, let scripts = mouseClick[region] {
                scripts
            } else {
                mouseClick["*"] ?? []
            }
        case let .choice(id, _):
            choices[id] ?? []
        }
    }
}

public enum DialogueCatalogError: LocalizedError {
    case invalidData(URL, Error)

    public var errorDescription: String? {
        switch self {
        case let .invalidData(url, error):
            "セリフデータを読み込めない: \(url.path) (\(error.localizedDescription))"
        }
    }
}

public struct DialogueCatalogLoader: Sendable {
    public init() {}

    public func load(from url: URL) throws -> DialogueCatalog {
        do {
            return try JSONDecoder().decode(DialogueCatalog.self, from: Data(contentsOf: url))
        } catch {
            throw DialogueCatalogError.invalidData(url, error)
        }
    }
}

public actor DialoguePersonalityEngine: PersonalityEngine {
    private let catalog: DialogueCatalog

    public init(catalog: DialogueCatalog) {
        self.catalog = catalog
    }

    public func handle(event: GhostEvent) async throws -> SakuraScript? {
        guard let source = catalog.scripts(for: event).randomElement() else { return nil }
        return SakuraScript(rawValue: applyArguments(to: source, event: event))
    }

    private func applyArguments(to source: String, event: GhostEvent) -> String {
        guard case let .choice(_, arguments) = event else { return source }
        return arguments.enumerated().reduce(source) { result, entry in
            result.replacingOccurrences(of: "{{argument\(entry.offset)}}", with: entry.element)
        }
    }
}
