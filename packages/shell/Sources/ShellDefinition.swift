import Foundation

public struct ShellDefinition: Sendable, Equatable {
    public let directory: URL
    public let surfaces: [Int: SurfaceDefinition]
    public let surfaceAliases: [Int: [String: [Int]]]

    public init(
        directory: URL,
        surfaces: [Int: SurfaceDefinition],
        surfaceAliases: [Int: [String: [Int]]] = [:]
    ) {
        self.directory = directory
        self.surfaces = surfaces
        self.surfaceAliases = surfaceAliases
    }

    public func resolveSurface(_ identifier: String, scope: Int) -> Int? {
        if let surfaceID = Int(identifier) {
            return surfaceID
        }
        return surfaceAliases[scope]?[identifier]?.randomElement()
    }
}

public struct SurfaceDefinition: Sendable, Equatable {
    public let id: Int
    public let collisions: [SurfaceCollision]
    public let animations: [SurfaceAnimation]

    public init(id: Int, collisions: [SurfaceCollision], animations: [SurfaceAnimation]) {
        self.id = id
        self.collisions = collisions
        self.animations = animations
    }
}

public struct SurfaceCollision: Sendable, Equatable {
    public let id: Int
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    public let name: String

    public init(id: Int, left: Int, top: Int, right: Int, bottom: Int, name: String) {
        self.id = id
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.name = name
    }

    public func contains(x: Int, y: Int) -> Bool {
        (min(left, right) ... max(left, right)).contains(x)
            && (min(top, bottom) ... max(top, bottom)).contains(y)
    }
}

public struct SurfaceAnimation: Sendable, Equatable {
    public let id: Int
    public let interval: String?
    public let patterns: [SurfaceAnimationPattern]

    public init(id: Int, interval: String?, patterns: [SurfaceAnimationPattern]) {
        self.id = id
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
