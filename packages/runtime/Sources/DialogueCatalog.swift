import Foundation
import UtataneCore
import UtataneSakuraScript

public struct DialogueCatalog: Codable, Sendable, Equatable {
    public let boot: [String]
    public let close: [String]
    public let ghostChanging: [String]
    public let randomTalk: [String]
    public let mouseClick: [String: [String]]
    public let choices: [String: [String]]

    public init(
        boot: [String] = [],
        close: [String] = [],
        ghostChanging: [String] = [],
        randomTalk: [String] = [],
        mouseClick: [String: [String]] = [:],
        choices: [String: [String]] = [:]
    ) {
        self.boot = boot
        self.close = close
        self.ghostChanging = ghostChanging
        self.randomTalk = randomTalk
        self.mouseClick = mouseClick
        self.choices = choices
    }

    public func scripts(for event: GhostEvent) -> [String] {
        switch event {
        case .boot:
            return boot
        case .close:
            return close
        case .ghostChanging:
            return ghostChanging.isEmpty ? close : ghostChanging
        case .randomTalk:
            return randomTalk
        case let .mouseClick(_, region):
            if let region, let scripts = mouseClick[region] {
                return scripts
            } else {
                return mouseClick["*"] ?? []
            }
        case let .mouse(event):
            guard case .click = event.kind else { return [] }
            if let region = event.region, let scripts = mouseClick[region] {
                return scripts
            } else {
                return mouseClick["*"] ?? []
            }
        case .shiori:
            return []
        case let .choice(id, _):
            return choices[id] ?? []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case boot
        case close
        case ghostChanging
        case randomTalk
        case mouseClick
        case choices
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boot = try container.decodeIfPresent([String].self, forKey: .boot) ?? []
        close = try container.decodeIfPresent([String].self, forKey: .close) ?? []
        ghostChanging = try container.decodeIfPresent([String].self, forKey: .ghostChanging) ?? []
        randomTalk = try container.decodeIfPresent([String].self, forKey: .randomTalk) ?? []
        mouseClick = try container.decodeIfPresent([String: [String]].self, forKey: .mouseClick) ?? [:]
        choices = try container.decodeIfPresent([String: [String]].self, forKey: .choices) ?? [:]
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
        switch event {
        case let .choice(_, arguments):
            arguments.enumerated().reduce(source) { result, entry in
                result.replacingOccurrences(of: "{{argument\(entry.offset)}}", with: entry.element)
            }
        case let .ghostChanging(name):
            source.replacingOccurrences(of: "{{ghostName}}", with: name ?? "")
        default:
            source
        }
    }
}
