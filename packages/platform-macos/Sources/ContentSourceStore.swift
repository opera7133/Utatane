import Combine
import Foundation

public enum ContentSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ghost
    case balloon
    case headline
    case plugin

    public var id: Self {
        self
    }
}

public struct ContentSource: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ContentSourceKind
    public var name: String
    public var directory: URL
    public var isEnabled: Bool
    public var priority: Int
    public var allowsAutomaticSwitching: Bool
    public var allowsAutomaticUpdates: Bool
    public let isBuiltIn: Bool

    public init(
        id: String,
        kind: ContentSourceKind,
        name: String,
        directory: URL,
        isEnabled: Bool = true,
        priority: Int = 0,
        allowsAutomaticSwitching: Bool = true,
        allowsAutomaticUpdates: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.directory = directory
        self.isEnabled = isEnabled
        self.priority = priority
        self.allowsAutomaticSwitching = allowsAutomaticSwitching
        self.allowsAutomaticUpdates = allowsAutomaticUpdates
        self.isBuiltIn = isBuiltIn
    }
}

public final class ContentSourceStore: ObservableObject {
    @Published public private(set) var sources: [ContentSource]

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaultSources: [ContentSource],
        defaults: UserDefaults = .standard,
        key: String = "content.sources"
    ) {
        self.defaults = defaults
        self.key = key
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ContentSource].self, from: $0) }
        sources = Self.merging(defaultSources: defaultSources, storedSources: stored ?? [])
        save()
    }

    public func enabledDirectories(for kind: ContentSourceKind) -> [URL] {
        var seen = Set<String>()
        return sources
            .filter { $0.kind == kind && $0.isEnabled }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority < rhs.priority
            }
            .compactMap { source in
                let directory = source.directory.standardizedFileURL
                guard seen.insert(directory.path).inserted else { return nil }
                return directory
            }
    }

    public func orderedSources(for kind: ContentSourceKind) -> [ContentSource] {
        sources
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority < rhs.priority
            }
    }

    @discardableResult
    public func add(kind: ContentSourceKind, name: String, directory: URL) -> ContentSource {
        let source = ContentSource(
            id: UUID().uuidString,
            kind: kind,
            name: name,
            directory: directory.standardizedFileURL,
            priority: nextPriority(for: kind)
        )
        sources.append(source)
        save()
        return source
    }

    public func update(_ source: ContentSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index] = source
        save()
    }

    public func remove(id: String) {
        guard let source = sources.first(where: { $0.id == id }), !source.isBuiltIn else { return }
        sources.removeAll { $0.id == id }
        normalizePriorities(for: source.kind)
        save()
    }

    public func move(kind: ContentSourceKind, fromOffsets: IndexSet, toOffset: Int) {
        var ordered = sources
            .filter { $0.kind == kind }
            .sorted { $0.priority < $1.priority }
        let moving = fromOffsets.sorted().compactMap { ordered.indices.contains($0) ? ordered[$0] : nil }
        for index in fromOffsets.sorted(by: >) where ordered.indices.contains(index) {
            ordered.remove(at: index)
        }
        let removedBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        let destination = min(max(0, toOffset - removedBeforeDestination), ordered.count)
        ordered.insert(contentsOf: moving, at: destination)
        for (priority, source) in ordered.enumerated() {
            guard let index = sources.firstIndex(where: { $0.id == source.id }) else { continue }
            sources[index].priority = priority
        }
        save()
    }

    private func nextPriority(for kind: ContentSourceKind) -> Int {
        (sources.filter { $0.kind == kind }.map(\.priority).max() ?? -1) + 1
    }

    private func normalizePriorities(for kind: ContentSourceKind) {
        let ordered = sources
            .filter { $0.kind == kind }
            .sorted { $0.priority < $1.priority }
        for (priority, source) in ordered.enumerated() {
            guard let index = sources.firstIndex(where: { $0.id == source.id }) else { continue }
            sources[index].priority = priority
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: key)
    }

    private static func merging(
        defaultSources: [ContentSource],
        storedSources: [ContentSource]
    ) -> [ContentSource] {
        var sources = storedSources
        for defaultSource in defaultSources {
            if let index = sources.firstIndex(where: { $0.id == defaultSource.id }) {
                let stored = sources[index]
                sources[index] = ContentSource(
                    id: defaultSource.id,
                    kind: defaultSource.kind,
                    name: defaultSource.name,
                    directory: defaultSource.directory,
                    isEnabled: stored.isEnabled,
                    priority: stored.priority,
                    allowsAutomaticSwitching: stored.allowsAutomaticSwitching,
                    allowsAutomaticUpdates: stored.allowsAutomaticUpdates,
                    isBuiltIn: true
                )
            } else {
                sources.append(defaultSource)
            }
        }
        return sources
    }
}
