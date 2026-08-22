import Foundation

public struct SurfaceTable: Sendable, Equatable {
    public let version: Int?
    public let options: Set<String>
    public let groups: [SurfaceTableGroup]

    public init(version: Int? = nil, options: Set<String> = [], groups: [SurfaceTableGroup] = []) {
        self.version = version
        self.options = options
        self.groups = groups
    }

    public var disablesUndefinedSurfaces: Bool {
        options.contains { $0.caseInsensitiveCompare("DisableNoDefineSurfaces") == .orderedSame }
    }

    public var entriesByID: [Int: SurfaceTableEntry] {
        groups.flatMap(\.entries).reduce(into: [:]) { result, entry in
            result[entry.id] = entry
        }
    }
}

public struct SurfaceTableGroup: Sendable, Equatable {
    public let name: String
    public let scope: Int?
    public let entries: [SurfaceTableEntry]

    public init(name: String, scope: Int?, entries: [SurfaceTableEntry]) {
        self.name = name
        self.scope = scope
        self.entries = entries
    }

    public var isDisabled: Bool {
        name == "__disabled"
    }
}

public struct SurfaceTableEntry: Sendable, Equatable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public var isPart: Bool {
        name == "__parts"
    }
}

public struct SurfaceTableParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> SurfaceTable {
        var version: Int?
        var options: Set<String> = []
        var groups: [SurfaceTableGroup] = []
        var groupName: String?
        var scope: Int?
        var entries: [SurfaceTableEntry] = []

        func finishGroup() -> SurfaceTableGroup? {
            guard let groupName else { return nil }
            return SurfaceTableGroup(name: groupName, scope: scope, entries: entries)
        }

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }
            if line == "{" {
                continue
            }
            if line == "}" {
                if let group = finishGroup() {
                    groups.append(group)
                }
                groupName = nil
                scope = nil
                entries = []
                continue
            }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let key = fields.first else { continue }
            if key.caseInsensitiveCompare("charset") == .orderedSame {
                continue
            }
            if key.caseInsensitiveCompare("version") == .orderedSame {
                version = fields.dropFirst().first.flatMap(Int.init)
            } else if key.caseInsensitiveCompare("option") == .orderedSame {
                options.formUnion(fields.dropFirst().filter { !$0.isEmpty })
            } else if key.caseInsensitiveCompare("group") == .orderedSame {
                if let group = finishGroup() {
                    groups.append(group)
                }
                groupName = fields.dropFirst().joined(separator: ",")
                scope = nil
                entries = []
            } else if key.caseInsensitiveCompare("scope") == .orderedSame {
                scope = fields.dropFirst().first.flatMap(Int.init)
            } else if groupName != nil, let id = Int(key) {
                entries.append(SurfaceTableEntry(
                    id: id,
                    name: fields.dropFirst().joined(separator: ",")
                ))
            }
        }
        if let group = finishGroup() {
            groups.append(group)
        }
        return SurfaceTable(version: version, options: options, groups: groups)
    }
}
