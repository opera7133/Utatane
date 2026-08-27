import Foundation

public struct ParsedSurfacesDocument: Sendable, Equatable {
    public let surfaces: [Int: SurfaceDefinition]
    public let aliases: [Int: [String: [Int]]]
    public let maximumSurfaceWidth: Int?
    public let collisionSort: SurfaceSortOrder
    public let animationSort: SurfaceSortOrder
    public let cursorDefinitions: [Int: [SurfaceCursorDefinition]]
    public let tooltips: [Int: [String: String]]

    public init(
        surfaces: [Int: SurfaceDefinition], aliases: [Int: [String: [Int]]],
        maximumSurfaceWidth: Int? = nil,
        collisionSort: SurfaceSortOrder = .none,
        animationSort: SurfaceSortOrder = .descending,
        cursorDefinitions: [Int: [SurfaceCursorDefinition]] = [:],
        tooltips: [Int: [String: String]] = [:]
    ) {
        self.surfaces = surfaces
        self.aliases = aliases
        self.maximumSurfaceWidth = maximumSurfaceWidth
        self.collisionSort = collisionSort
        self.animationSort = animationSort
        self.cursorDefinitions = cursorDefinitions
        self.tooltips = tooltips
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
        var maximumSurfaceWidth: Int?
        var collisionSort: SurfaceSortOrder = .none
        var animationSort: SurfaceSortOrder = .descending
        var cursorDefinitions: [Int: [SurfaceCursorDefinition]] = [:]
        var tooltips: [Int: [String: String]] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
                .replacingOccurrences(of: #"\s+//.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
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
            case .descript:
                let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
                guard fields.count == 2 else { continue }
                switch fields[0].lowercased() {
                case "maxwidth": maximumSurfaceWidth = Int(fields[1])
                case "collision-sort": collisionSort = SurfaceSortOrder(rawValue: fields[1].lowercased()) ?? .none
                case "animation-sort": animationSort = SurfaceSortOrder(rawValue: fields[1].lowercased()) ?? .descending
                default: continue
                }
            case let .cursor(scope):
                guard let definition = parseCursor(line) else { continue }
                cursorDefinitions[scope, default: []].append(definition)
            case let .tooltips(scope):
                guard let separator = line.firstIndex(of: ",") else { continue }
                let region = line[..<separator].trimmingCharacters(in: .whitespaces)
                let text = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                guard !region.isEmpty, !text.isEmpty else { continue }
                tooltips[scope, default: [:]][region] = text
            case nil:
                continue
            }
        }

        return ParsedSurfacesDocument(
            surfaces: builders.mapValues { $0.build(collisionSort: collisionSort, animationSort: animationSort) },
            aliases: aliases,
            maximumSurfaceWidth: maximumSurfaceWidth,
            collisionSort: collisionSort,
            animationSort: animationSort,
            cursorDefinitions: cursorDefinitions,
            tooltips: tooltips
        )
    }

    private func parseBlockHeader(_ line: String) -> Block? {
        if line.lowercased() == "descript" {
            return .descript
        }
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
        if let scope = scopedBlock(line, suffix: ".cursor") {
            return .cursor(scope: scope)
        }
        if let scope = scopedBlock(line, suffix: ".tooltips") {
            return .tooltips(scope: scope)
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

    private func scopedBlock(_ line: String, suffix: String) -> Int? {
        if line == "sakura\(suffix)" {
            return 0
        }
        if line == "kero\(suffix)" {
            return 1
        }
        guard line.hasPrefix("char"), line.hasSuffix(suffix) else {
            return nil
        }
        let end = line.index(line.endIndex, offsetBy: -suffix.count)
        return Int(line[line.index(line.startIndex, offsetBy: 4) ..< end])
    }

    private func parseCursor(_ line: String) -> SurfaceCursorDefinition? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count >= 3, !fields[1].isEmpty, !fields[2].isEmpty else { return nil }
        let key = fields[0].lowercased().replacingOccurrences(of: #"\d+$"#, with: "", options: .regularExpression)
        let trigger: SurfaceCursorTrigger? = switch key {
        case "mouseup": .mouseUp
        case "mousedown": .mouseDown
        case "mouserightdown": .mouseRightDown
        case "mousewheel": .mouseWheel
        case "mousehover": .mouseHover
        default: nil
        }
        return trigger.map { SurfaceCursorDefinition(trigger: $0, region: fields[1], cursor: fields[2]) }
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

        if key == "name" {
            builder.name = values.first
            return
        }
        if ["balloon.offsetx", "offset.x"].contains(key), let value = values.first.flatMap(Int.init) {
            builder.balloonOffsetX = value
            return
        }
        if ["balloon.offsety", "offset.y"].contains(key), let value = values.first.flatMap(Int.init) {
            builder.balloonOffsetY = value
            return
        }
        let scopeOffsets = ["sakura": 0, "kero": 1]
        for (prefix, scope) in scopeOffsets {
            if key == "\(prefix).balloon.offsetx", let value = values.first.flatMap(Int.init) {
                builder.scopeBalloonOffsetX[scope] = value
                return
            }
            if key == "\(prefix).balloon.offsety", let value = values.first.flatMap(Int.init) {
                builder.scopeBalloonOffsetY[scope] = value
                return
            }
        }
        let pointComponents = [
            "point.centerx": ("center", true), "point.centery": ("center", false),
            "point.kinoko.centerx": ("kinoko.center", true), "point.kinoko.centery": ("kinoko.center", false),
            "point.basepos.x": ("basepos", true), "point.basepos.y": ("basepos", false)
        ]
        if let (name, isX) = pointComponents[key], let value = values.first.flatMap(Int.init) {
            if isX {
                builder.pointX[name] = value
            } else {
                builder.pointY[name] = value
            }
            return
        }
        if key == "icon.rect", values.count >= 4,
           let left = Int(values[0]), let top = Int(values[1]),
           let right = Int(values[2]), let bottom = Int(values[3])
        {
            builder.iconRect = SurfaceRect(left: left, top: top, right: right, bottom: bottom)
            return
        }

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
            if builder.collisions[collisionID] == nil {
                builder.collisionOrder.append(collisionID)
            }
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

        if key.hasPrefix("collisionex"),
           let collisionID = Int(key.dropFirst("collisionex".count)),
           values.count >= 5
        {
            if builder.collisions[collisionID] == nil {
                builder.collisionOrder.append(collisionID)
            }
            let name = values[0]
            let shape = values[1].lowercased()
            let coordinates = values.dropFirst(2).compactMap(Int.init)
            if shape == "rect", coordinates.count >= 4 {
                builder.collisions[collisionID] = SurfaceCollision(
                    id: collisionID,
                    left: coordinates[0],
                    top: coordinates[1],
                    right: coordinates[2],
                    bottom: coordinates[3],
                    name: name
                )
            } else if shape == "ellipse", coordinates.count >= 4 {
                builder.collisions[collisionID] = SurfaceCollision(
                    id: collisionID,
                    left: coordinates[0],
                    top: coordinates[1],
                    right: coordinates[2],
                    bottom: coordinates[3],
                    name: name,
                    shape: .ellipse
                )
            } else if shape == "circle", coordinates.count >= 3 {
                let center = SurfacePoint(x: coordinates[0], y: coordinates[1])
                let radius = coordinates[2]
                builder.collisions[collisionID] = SurfaceCollision(
                    id: collisionID,
                    left: center.x - radius,
                    top: center.y - radius,
                    right: center.x + radius,
                    bottom: center.y + radius,
                    name: name,
                    shape: .circle(center: center, radius: radius)
                )
            } else if shape == "polygon", coordinates.count >= 6, coordinates.count.isMultiple(of: 2) {
                let points = stride(from: 0, to: coordinates.count, by: 2).map {
                    SurfacePoint(x: coordinates[$0], y: coordinates[$0 + 1])
                }
                builder.collisions[collisionID] = SurfaceCollision(
                    id: collisionID,
                    left: points.map(\.x).min() ?? 0,
                    top: points.map(\.y).min() ?? 0,
                    right: points.map(\.x).max() ?? 0,
                    bottom: points.map(\.y).max() ?? 0,
                    name: name,
                    polygon: points
                )
            }
            return
        }

        let animationID: Int
        let directive: String
        let legacySyntax: Bool
        if key.hasPrefix("animation") {
            let animationKey = key.dropFirst("animation".count).split(separator: ".", maxSplits: 1)
            guard animationKey.count == 2, let parsedID = Int(animationKey[0]) else { return }
            animationID = parsedID
            directive = String(animationKey[1])
            legacySyntax = false
        } else {
            let idPrefix = key.prefix(while: { $0.isNumber })
            guard !idPrefix.isEmpty, let parsedID = Int(idPrefix) else { return }
            animationID = parsedID
            directive = String(key.dropFirst(idPrefix.count))
            legacySyntax = true
        }

        if builder.animations[animationID] == nil {
            builder.animationOrder.append(animationID)
        }
        var animation = builder.animations[animationID] ?? AnimationBuilder(id: animationID)
        if directive == "name" {
            animation.name = values.first
        } else if directive == "interval" {
            animation.interval = values.first
            animation.intervalParameter = values.dropFirst().first.flatMap(Int.init)
        } else if directive == "option" {
            animation.options.formUnion(values.first?.lowercased().split(separator: "+").map(String.init) ?? [])
        } else if directive.hasPrefix("collisionex"),
                  let collisionID = Int(directive.dropFirst("collisionex".count)),
                  values.count >= 4
        {
            let name = values[0]
            let shape = values[1].lowercased()
            let coordinates = values.dropFirst(2).compactMap(Int.init)
            if shape == "rect", coordinates.count >= 4 {
                animation.collisions[collisionID] = SurfaceCollision(
                    id: collisionID, left: coordinates[0], top: coordinates[1],
                    right: coordinates[2], bottom: coordinates[3], name: name
                )
            } else if shape == "ellipse", coordinates.count >= 4 {
                animation.collisions[collisionID] = SurfaceCollision(
                    id: collisionID, left: coordinates[0], top: coordinates[1],
                    right: coordinates[2], bottom: coordinates[3], name: name, shape: .ellipse
                )
            } else if shape == "circle", coordinates.count >= 3 {
                let center = SurfacePoint(x: coordinates[0], y: coordinates[1])
                animation.collisions[collisionID] = SurfaceCollision(
                    id: collisionID, left: center.x - coordinates[2], top: center.y - coordinates[2],
                    right: center.x + coordinates[2], bottom: center.y + coordinates[2], name: name,
                    shape: .circle(center: center, radius: coordinates[2])
                )
            } else if shape == "polygon", coordinates.count >= 6, coordinates.count.isMultiple(of: 2) {
                let points = stride(from: 0, to: coordinates.count, by: 2).map {
                    SurfacePoint(x: coordinates[$0], y: coordinates[$0 + 1])
                }
                animation.collisions[collisionID] = SurfaceCollision(
                    id: collisionID, left: points.map(\.x).min() ?? 0, top: points.map(\.y).min() ?? 0,
                    right: points.map(\.x).max() ?? 0, bottom: points.map(\.y).max() ?? 0,
                    name: name, polygon: points
                )
            }
        } else if directive.hasPrefix("collision"),
                  let collisionID = Int(directive.dropFirst("collision".count)),
                  values.count >= 5,
                  let left = Int(values[0]), let top = Int(values[1]),
                  let right = Int(values[2]), let bottom = Int(values[3])
        {
            animation.collisions[collisionID] = SurfaceCollision(
                id: collisionID, left: left, top: top, right: right, bottom: bottom, name: values[4]
            )
        } else if directive.hasPrefix("pattern"),
                  let order = Int(directive.dropFirst("pattern".count)),
                  values.count >= 2,
                  let surfaceID = Int(values[legacySyntax ? 0 : 1])
        {
            // SERIKO's stop pattern has no wait field:
            // animation101.pattern0,stop,100
            let waitIndex = legacySyntax ? 1 : 2
            let methodIndex = legacySyntax ? 2 : 0
            let coordinateStart = legacySyntax ? 3 : 3
            let wait = values.count > waitIndex ? Int(values[waitIndex]) ?? 0 : 0
            animation.patterns[order] = SurfaceAnimationPattern(
                order: order,
                method: values.count > methodIndex ? values[methodIndex] : "overlay",
                surfaceID: surfaceID,
                waitMilliseconds: wait,
                x: values.count > coordinateStart ? Int(values[coordinateStart]) ?? 0 : 0,
                y: values.count > coordinateStart + 1 ? Int(values[coordinateStart + 1]) ?? 0 : 0
            )
        }
        builder.animations[animationID] = animation
    }
}

private enum Block {
    case surfaces(ids: [Int], appendOnly: Bool)
    case aliases(scope: Int)
    case descript
    case cursor(scope: Int)
    case tooltips(scope: Int)
}

private struct SurfaceBuilder {
    let id: Int
    var name: String?
    var balloonOffsetX: Int?
    var balloonOffsetY: Int?
    var scopeBalloonOffsetX: [Int: Int] = [:]
    var scopeBalloonOffsetY: [Int: Int] = [:]
    var pointX: [String: Int] = [:]
    var pointY: [String: Int] = [:]
    var iconRect: SurfaceRect?
    var elements: [Int: SurfaceElement] = [:]
    var collisions: [Int: SurfaceCollision] = [:]
    var collisionOrder: [Int] = []
    var animations: [Int: AnimationBuilder] = [:]
    var animationOrder: [Int] = []

    func build(collisionSort: SurfaceSortOrder, animationSort: SurfaceSortOrder) -> SurfaceDefinition {
        let collisionIDs = sortedIDs(collisionOrder, order: collisionSort)
        let animationIDs = sortedIDs(animationOrder, order: animationSort)
        return SurfaceDefinition(
            id: id,
            name: name,
            balloonOffset: point(x: balloonOffsetX, y: balloonOffsetY),
            scopeBalloonOffsets: Dictionary(uniqueKeysWithValues: Set(scopeBalloonOffsetX.keys)
                .union(scopeBalloonOffsetY.keys).map {
                    ($0, point(x: scopeBalloonOffsetX[$0], y: scopeBalloonOffsetY[$0]) ?? SurfacePoint(x: 0, y: 0))
                }),
            points: Dictionary(uniqueKeysWithValues: Set(pointX.keys).union(pointY.keys).map {
                ($0, point(x: pointX[$0], y: pointY[$0]) ?? SurfacePoint(x: 0, y: 0))
            }),
            iconRect: iconRect,
            elements: elements.values.sorted { $0.id < $1.id },
            collisions: collisionIDs.compactMap { collisions[$0] },
            animations: animationIDs.compactMap { animations[$0]?.build() },
            collisionSort: collisionSort,
            animationSort: animationSort
        )
    }

    private func sortedIDs(_ ids: [Int], order: SurfaceSortOrder) -> [Int] {
        switch order {
        case .none: ids
        case .ascending: ids.sorted()
        case .descending: ids.sorted(by: >)
        }
    }

    private func point(x: Int?, y: Int?) -> SurfacePoint? {
        guard x != nil || y != nil else { return nil }
        return SurfacePoint(x: x ?? 0, y: y ?? 0)
    }
}

private struct AnimationBuilder {
    let id: Int
    var name: String?
    var interval: String?
    var intervalParameter: Int?
    var options: Set<String> = []
    var collisions: [Int: SurfaceCollision] = [:]
    var patterns: [Int: SurfaceAnimationPattern] = [:]

    func build() -> SurfaceAnimation {
        SurfaceAnimation(
            id: id,
            name: name,
            interval: interval,
            intervalParameter: intervalParameter,
            options: options,
            collisions: collisions.values.sorted { $0.id < $1.id },
            patterns: patterns.values.sorted { $0.order < $1.order }
        )
    }
}
