import Foundation

public struct ShellDefinition: Sendable, Equatable {
    public let directory: URL
    public let surfaces: [Int: SurfaceDefinition]
    public let surfaceAliases: [Int: [String: [Int]]]
    public let usesSelfAlpha: Bool
    public let defaultBindGroups: [Int: Set<Int>]
    public let bindGroups: [Int: [Int: ShellBindGroup]]
    public let bindOptions: [Int: [String: ShellBindOptions]]
    public let surfaceTable: SurfaceTable?
    public let maximumSurfaceWidth: Int?
    public let cursorDefinitions: [Int: [SurfaceCursorDefinition]]
    public let tooltips: [Int: [String: String]]

    public init(
        directory: URL,
        surfaces: [Int: SurfaceDefinition],
        surfaceAliases: [Int: [String: [Int]]] = [:],
        usesSelfAlpha: Bool = false,
        defaultBindGroups: [Int: Set<Int>] = [:],
        bindGroups: [Int: [Int: ShellBindGroup]] = [:],
        bindOptions: [Int: [String: ShellBindOptions]] = [:]
    ) {
        self.init(
            directory: directory,
            surfaces: surfaces,
            surfaceAliases: surfaceAliases,
            usesSelfAlpha: usesSelfAlpha,
            defaultBindGroups: defaultBindGroups,
            bindGroups: bindGroups,
            bindOptions: bindOptions,
            surfaceTable: nil
        )
    }

    public init(
        directory: URL,
        surfaces: [Int: SurfaceDefinition],
        surfaceAliases: [Int: [String: [Int]]] = [:],
        usesSelfAlpha: Bool = false,
        defaultBindGroups: [Int: Set<Int>] = [:],
        bindGroups: [Int: [Int: ShellBindGroup]] = [:],
        bindOptions: [Int: [String: ShellBindOptions]] = [:],
        surfaceTable: SurfaceTable?
    ) {
        self.init(
            directory: directory,
            surfaces: surfaces,
            surfaceAliases: surfaceAliases,
            usesSelfAlpha: usesSelfAlpha,
            defaultBindGroups: defaultBindGroups,
            bindGroups: bindGroups,
            bindOptions: bindOptions,
            surfaceTable: surfaceTable,
            maximumSurfaceWidth: nil
        )
    }

    public init(
        directory: URL,
        surfaces: [Int: SurfaceDefinition],
        surfaceAliases: [Int: [String: [Int]]] = [:],
        usesSelfAlpha: Bool = false,
        defaultBindGroups: [Int: Set<Int>] = [:],
        bindGroups: [Int: [Int: ShellBindGroup]] = [:],
        bindOptions: [Int: [String: ShellBindOptions]] = [:],
        surfaceTable: SurfaceTable?,
        maximumSurfaceWidth: Int?,
        cursorDefinitions: [Int: [SurfaceCursorDefinition]] = [:],
        tooltips: [Int: [String: String]] = [:]
    ) {
        self.directory = directory
        self.surfaces = surfaces
        self.surfaceAliases = surfaceAliases
        self.usesSelfAlpha = usesSelfAlpha
        self.defaultBindGroups = defaultBindGroups
        self.bindGroups = bindGroups
        self.bindOptions = bindOptions
        self.surfaceTable = surfaceTable
        self.maximumSurfaceWidth = maximumSurfaceWidth
        self.cursorDefinitions = cursorDefinitions
        self.tooltips = tooltips
    }

    public func resolveSurface(_ identifier: String, scope: Int) -> Int? {
        if let aliasedSurfaceID = surfaceAliases[scope]?[identifier]?.randomElement() {
            return aliasedSurfaceID
        }
        return Int(identifier)
    }

    public func effectiveBindGroups(scope: Int, enabled: Set<Int>) -> Set<Int> {
        var result = enabled
        var pending = Array(enabled)
        while let id = pending.popLast() {
            for addedID in bindGroups[scope]?[id]?.addIDs ?? [] where result.insert(addedID).inserted {
                pending.append(addedID)
            }
        }
        return result
    }
}

public enum SurfaceCursorTrigger: String, Sendable, Equatable {
    case mouseUp
    case mouseDown
    case mouseRightDown
    case mouseWheel
    case mouseHover
}

public struct SurfaceCursorDefinition: Sendable, Equatable {
    public let trigger: SurfaceCursorTrigger
    public let region: String
    public let cursor: String

    public init(trigger: SurfaceCursorTrigger, region: String, cursor: String) {
        self.trigger = trigger
        self.region = region
        self.cursor = cursor
    }
}

public enum SurfaceSortOrder: String, Sendable, Equatable {
    case none
    case ascending = "ascend"
    case descending = "descend"
}

public struct ShellBindGroup: Sendable, Equatable {
    public let id: Int
    public let category: String
    public let part: String
    public let thumbnail: String
    public let addIDs: Set<Int>

    public init(id: Int, category: String, part: String, thumbnail: String = "", addIDs: Set<Int> = []) {
        self.id = id
        self.category = category
        self.part = part
        self.thumbnail = thumbnail
        self.addIDs = addIDs
    }
}

public struct ShellBindOptions: Sendable, Equatable {
    public let mustSelect: Bool
    public let multiple: Bool

    public init(mustSelect: Bool = false, multiple: Bool = false) {
        self.mustSelect = mustSelect
        self.multiple = multiple
    }
}

public struct SurfaceDefinition: Sendable, Equatable {
    public let id: Int
    public let name: String?
    public let balloonOffset: SurfacePoint?
    public let scopeBalloonOffsets: [Int: SurfacePoint]
    public let points: [String: SurfacePoint]
    public let iconRect: SurfaceRect?
    public let elements: [SurfaceElement]
    public let collisions: [SurfaceCollision]
    public let animations: [SurfaceAnimation]
    public let collisionSort: SurfaceSortOrder
    public let animationSort: SurfaceSortOrder

    public init(
        id: Int,
        name: String? = nil,
        balloonOffset: SurfacePoint? = nil,
        scopeBalloonOffsets: [Int: SurfacePoint] = [:],
        points: [String: SurfacePoint] = [:],
        iconRect: SurfaceRect? = nil,
        elements: [SurfaceElement] = [],
        collisions: [SurfaceCollision],
        animations: [SurfaceAnimation]
    ) {
        self.init(
            id: id,
            name: name,
            balloonOffset: balloonOffset,
            scopeBalloonOffsets: scopeBalloonOffsets,
            points: points,
            iconRect: iconRect,
            elements: elements,
            collisions: collisions,
            animations: animations,
            collisionSort: .none,
            animationSort: .descending
        )
    }

    public init(
        id: Int,
        name: String? = nil,
        balloonOffset: SurfacePoint? = nil,
        scopeBalloonOffsets: [Int: SurfacePoint] = [:],
        points: [String: SurfacePoint] = [:],
        iconRect: SurfaceRect? = nil,
        elements: [SurfaceElement] = [],
        collisions: [SurfaceCollision],
        animations: [SurfaceAnimation],
        collisionSort: SurfaceSortOrder,
        animationSort: SurfaceSortOrder
    ) {
        self.id = id
        self.name = name
        self.balloonOffset = balloonOffset
        self.scopeBalloonOffsets = scopeBalloonOffsets
        self.points = points
        self.iconRect = iconRect
        self.elements = elements
        self.collisions = collisions
        self.animations = animations
        self.collisionSort = collisionSort
        self.animationSort = animationSort
    }
}

public struct SurfaceRect: Sendable, Equatable {
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int

    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

public struct SurfaceElement: Sendable, Equatable {
    public let id: Int
    public let method: String
    public let filename: String
    public let x: Int
    public let y: Int

    public init(id: Int, method: String, filename: String, x: Int, y: Int) {
        self.id = id
        self.method = method
        self.filename = filename
        self.x = x
        self.y = y
    }
}

public struct SurfaceCollision: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case rectangle
        case ellipse
        case circle(center: SurfacePoint, radius: Int)
        case polygon
    }

    public let id: Int
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    public let name: String
    public let polygon: [SurfacePoint]
    public let shape: Shape

    public init(
        id: Int,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        name: String,
        polygon: [SurfacePoint] = [],
        shape: Shape? = nil
    ) {
        self.id = id
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.name = name
        self.polygon = polygon
        self.shape = shape ?? (polygon.isEmpty ? .rectangle : .polygon)
    }

    public func contains(x: Int, y: Int) -> Bool {
        switch shape {
        case .polygon where polygon.count >= 3:
            var inside = false
            var previous = polygon.count - 1
            for current in polygon.indices {
                let a = polygon[current]
                let b = polygon[previous]
                if (a.y > y) != (b.y > y),
                   Double(x) < Double(b.x - a.x) * Double(y - a.y) / Double(b.y - a.y) + Double(a.x)
                {
                    inside.toggle()
                }
                previous = current
            }
            return inside
        case .ellipse:
            let centerX = Double(left + right) / 2
            let centerY = Double(top + bottom) / 2
            let radiusX = Double(abs(right - left)) / 2
            let radiusY = Double(abs(bottom - top)) / 2
            guard radiusX > 0, radiusY > 0 else { return false }
            return pow((Double(x) - centerX) / radiusX, 2) + pow((Double(y) - centerY) / radiusY, 2) <= 1
        case let .circle(center, radius):
            let dx = x - center.x
            let dy = y - center.y
            return dx * dx + dy * dy <= radius * radius
        default:
            return (min(left, right) ... max(left, right)).contains(x)
                && (min(top, bottom) ... max(top, bottom)).contains(y)
        }
    }
}

public struct SurfacePoint: Sendable, Equatable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct SurfaceAnimation: Sendable, Equatable {
    public let id: Int
    public let name: String?
    public let interval: String?
    public let intervalParameter: Int?
    public let options: Set<String>
    public let collisions: [SurfaceCollision]
    public let patterns: [SurfaceAnimationPattern]

    public init(
        id: Int,
        name: String? = nil,
        interval: String?,
        options: Set<String> = [],
        collisions: [SurfaceCollision] = [],
        patterns: [SurfaceAnimationPattern]
    ) {
        self.init(
            id: id,
            name: name,
            interval: interval,
            intervalParameter: nil,
            options: options,
            collisions: collisions,
            patterns: patterns
        )
    }

    public init(
        id: Int,
        name: String? = nil,
        interval: String?,
        intervalParameter: Int?,
        options: Set<String> = [],
        collisions: [SurfaceCollision] = [],
        patterns: [SurfaceAnimationPattern]
    ) {
        self.id = id
        self.name = name
        self.interval = interval
        self.intervalParameter = intervalParameter
        self.options = options
        self.collisions = collisions
        self.patterns = patterns
    }
}

public struct SurfaceAnimationPattern: Sendable, Equatable {
    public let order: Int
    public let method: String
    public let surfaceID: Int
    public let waitMilliseconds: Int
    public let x: Int
    public let y: Int

    public init(
        order: Int,
        method: String,
        surfaceID: Int,
        waitMilliseconds: Int,
        x: Int,
        y: Int
    ) {
        self.order = order
        self.method = method
        self.surfaceID = surfaceID
        self.waitMilliseconds = waitMilliseconds
        self.x = x
        self.y = y
    }
}
