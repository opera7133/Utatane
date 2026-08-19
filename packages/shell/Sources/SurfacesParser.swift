import Foundation

public struct ParsedSurfacesDocument: Sendable, Equatable {
    public let surfaces: [Int: SurfaceDefinition]
    public let aliases: [Int: [String: [Int]]]

    public init(surfaces: [Int: SurfaceDefinition], aliases: [Int: [String: [Int]]]) {
        self.surfaces = surfaces
        self.aliases = aliases
    }
}

public struct SurfacesParser: Sendable {
    public init() {}

    public func parse(_ text: String, existingSurfaceIDs: Set<Int> = []) -> [Int: SurfaceDefinition] {
        parseDocument(text, existingSurfaceIDs: existingSurfaceIDs).surfaces
    }

    public func parseDocument(
        _ text: String,
        existingSurfaceIDs: Set<Int> = []
    ) -> ParsedSurfacesDocument {
        var builders = Dictionary(uniqueKeysWithValues: existingSurfaceIDs.map {
            ($0, SurfaceBuilder(id: $0))
        })
        var aliases: [Int: [String: [Int]]] = [:]
        var pendingBlock: Block?
        var currentBlock: Block?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//") else { continue }

            if let block = parseBlockHeader(line) {
                pendingBlock = block
                continue
            }
            if line == "{" {
                currentBlock = pendingBlock
                pendingBlock = nil
                continue
            }
            if line == "}" {
                currentBlock = nil
                continue
            }

            switch currentBlock {
            case let .surfaces(surfaceIDs, appendOnly):
                for surfaceID in surfaceIDs where !appendOnly || builders[surfaceID] != nil {
                    var builder = builders[surfaceID] ?? SurfaceBuilder(id: surfaceID)
                    parseDirective(line, into: &builder)
                    builders[surfaceID] = builder
                }
            case let .aliases(scope):
                guard let (name, surfaceIDs) = parseAlias(line) else { continue }
                aliases[scope, default: [:]][name] = surfaceIDs
            case nil:
                continue
            }
        }

        return ParsedSurfacesDocument(
            surfaces: builders.mapValues { $0.build() },
            aliases: aliases
        )
    }

    private func parseBlockHeader(_ line: String) -> Block? {
        if line == "sakura.surface.alias" {
            return .aliases(scope: 0)
        }
        if line == "kero.surface.alias" {
            return .aliases(scope: 1)
        }
        if line.hasPrefix("char"), line.hasSuffix(".surface.alias") {
            let end = line.index(line.endIndex, offsetBy: -".surface.alias".count)
            if let scope = Int(line[line.index(line.startIndex, offsetBy: 4) ..< end]) {
                return .aliases(scope: scope)
            }
        }

        let appendPrefix = "surface.append"
        let surfacePrefix = "surface"
        let appendOnly: Bool
        let selector: Substring
        if line.hasPrefix(appendPrefix) {
            appendOnly = true
            selector = line.dropFirst(appendPrefix.count)
        } else if line.hasPrefix(surfacePrefix), !line.contains(".alias") {
            appendOnly = false
            selector = line.dropFirst(surfacePrefix.count)
        } else {
            return nil
        }

        let surfaceIDs = parseSurfaceSelector(String(selector))
        return surfaceIDs.isEmpty ? nil : .surfaces(ids: surfaceIDs, appendOnly: appendOnly)
    }

    private func parseSurfaceSelector(_ selector: String) -> [Int] {
        let parts = selector.split(separator: ",", omittingEmptySubsequences: true)
        var included = Set<Int>()
        var excluded = Set<Int>()

        for rawPart in parts {
            var part = rawPart.trimmingCharacters(in: .whitespaces)
            let isExcluded = part.hasPrefix("!")
            if isExcluded {
                part.removeFirst()
            }
            if part.hasPrefix("surface") {
                part.removeFirst("surface".count)
            }
            let values = expandIDs(part)
            if isExcluded {
                excluded.formUnion(values)
            } else {
                included.formUnion(values)
            }
        }
        return included.subtracting(excluded).sorted()
    }

    private func expandIDs(_ source: String) -> [Int] {
        let bounds = source.split(separator: "-", omittingEmptySubsequences: false)
        if bounds.count == 1, let value = Int(bounds[0]) {
            return [value]
        }
        guard bounds.count == 2,
              let start = Int(bounds[0]),
              let end = Int(bounds[1])
        else {
            return []
        }
        return start <= end ? Array(start ... end) : Array((end ... start).reversed())
    }

    private func parseAlias(_ line: String) -> (String, [Int])? {
        guard let separator = line.firstIndex(of: ",") else { return nil }
        let name = line[..<separator].trimmingCharacters(in: .whitespaces)
        var values = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard values.hasPrefix("["), values.hasSuffix("]") else { return nil }
        values.removeFirst()
        values.removeLast()
        let surfaceIDs = values.split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        return surfaceIDs.isEmpty ? nil : (name, surfaceIDs)
    }

    private func parseDirective(_ line: String, into builder: inout SurfaceBuilder) {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let key = fields.first else { return }
        let values = Array(fields.dropFirst())

        if key.hasPrefix("element"),
           let elementID = Int(key.dropFirst("element".count)),
           values.count >= 4,
           let x = Int(values[2]),
           let y = Int(values[3])
        {
            builder.elements[elementID] = SurfaceElement(
                id: elementID,
                method: values[0],
                filename: values[1],
                x: x,
                y: y
            )
            return
        }

        if key.hasPrefix("collision"),
           let collisionID = Int(key.dropFirst("collision".count)),
           values.count >= 5,
           let left = Int(values[0]),
           let top = Int(values[1]),
           let right = Int(values[2]),
           let bottom = Int(values[3])
        {
            builder.collisions[collisionID] = SurfaceCollision(
                id: collisionID,
                left: left,
                top: top,
                right: right,
                bottom: bottom,
                name: values[4]
            )
            return
        }

        guard key.hasPrefix("animation") else { return }
        let animationKey = key.dropFirst("animation".count).split(separator: ".", maxSplits: 1)
        guard animationKey.count == 2, let animationID = Int(animationKey[0]) else { return }

        var animation = builder.animations[animationID] ?? AnimationBuilder(id: animationID)
        if animationKey[1] == "interval" {
            animation.interval = values.first
        } else if animationKey[1].hasPrefix("pattern"),
                  let order = Int(animationKey[1].dropFirst("pattern".count)),
                  values.count >= 3,
                  let surfaceID = Int(values[1]),
                  let wait = Int(values[2])
        {
            animation.patterns[order] = SurfaceAnimationPattern(
                order: order,
                method: values[0],
                surfaceID: surfaceID,
                waitMilliseconds: wait,
                x: values.count > 3 ? Int(values[3]) ?? 0 : 0,
                y: values.count > 4 ? Int(values[4]) ?? 0 : 0
            )
        }
        builder.animations[animationID] = animation
    }
}

private enum Block {
    case surfaces(ids: [Int], appendOnly: Bool)
    case aliases(scope: Int)
}

private struct SurfaceBuilder {
    let id: Int
    var elements: [Int: SurfaceElement] = [:]
    var collisions: [Int: SurfaceCollision] = [:]
    var animations: [Int: AnimationBuilder] = [:]

    func build() -> SurfaceDefinition {
        SurfaceDefinition(
            id: id,
            elements: elements.values.sorted { $0.id < $1.id },
            collisions: collisions.values.sorted { $0.id < $1.id },
            animations: animations.values.map { $0.build() }.sorted { $0.id < $1.id }
        )
    }
}

private struct AnimationBuilder {
    let id: Int
    var interval: String?
    var patterns: [Int: SurfaceAnimationPattern] = [:]

    func build() -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            interval: interval,
            patterns: patterns.values.sorted { $0.order < $1.order }
        )
    }
}
