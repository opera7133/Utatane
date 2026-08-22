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
        self.directory = directory
        self.surfaces = surfaces
        self.surfaceAliases = surfaceAliases
        self.usesSelfAlpha = usesSelfAlpha
        self.defaultBindGroups = defaultBindGroups
        self.bindGroups = bindGroups
        self.bindOptions = bindOptions
        self.surfaceTable = surfaceTable
    }

    public func resolveSurface(_ identifier: String, scope: Int) -> Int? {
        if let surfaceID = Int(identifier) {
            return surfaceID
        }
        return surfaceAliases[scope]?[identifier]?.randomElement()
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
    public let elements: [SurfaceElement]
    public let collisions: [SurfaceCollision]
    public let animations: [SurfaceAnimation]

    public init(
        id: Int,
        elements: [SurfaceElement] = [],
        collisions: [SurfaceCollision],
        animations: [SurfaceAnimation]
    ) {
        self.id = id
        self.elements = elements
        self.collisions = collisions
        self.animations = animations
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
    public let id: Int
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    public let name: String
    public let polygon: [SurfacePoint]

    public init(
        id: Int,
        left: Int,
        top: Int,
        right: Int,
        bottom: Int,
        name: String,
        polygon: [SurfacePoint] = []
    ) {
        self.id = id
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.name = name
        self.polygon = polygon
    }

    public func contains(x: Int, y: Int) -> Bool {
        if polygon.count >= 3 {
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
        }
        return (min(left, right) ... max(left, right)).contains(x)
            && (min(top, bottom) ... max(top, bottom)).contains(y)
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
    public let patterns: [SurfaceAnimationPattern]

    public init(id: Int, name: String? = nil, interval: String?, patterns: [SurfaceAnimationPattern]) {
        self.id = id
        self.name = name
        self.interval = interval
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
