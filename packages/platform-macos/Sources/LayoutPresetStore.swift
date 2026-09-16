import AppKit
import Foundation

public struct LayoutPresetGhost: Codable, Equatable, Sendable {
    public let ghostPath: String
    public let shellPath: String
    public let balloonPath: String
    public let positions: [Int: CGPoint]
    public let balloonPositions: [Int: CGPoint]
    public let stageFrame: CGRect?

    public init(
        ghostPath: String, shellPath: String, balloonPath: String,
        positions: [Int: CGPoint], balloonPositions: [Int: CGPoint] = [:], stageFrame: CGRect? = nil
    ) {
        self.ghostPath = ghostPath
        self.shellPath = shellPath
        self.balloonPath = balloonPath
        self.positions = positions
        self.balloonPositions = balloonPositions
        self.stageFrame = stageFrame
    }
}

public struct LayoutPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let ghosts: [LayoutPresetGhost]
    public let windowMode: String
    public let shellPercent: Int
    public let balloonPercent: Int
    public let textPercent: Int
    public let linksBalloonScale: Bool
    public let automaticallyFitsLargeSurfaces: Bool

    public init(
        id: UUID = UUID(), name: String, ghosts: [LayoutPresetGhost], windowMode: String,
        shellPercent: Int, balloonPercent: Int, textPercent: Int, linksBalloonScale: Bool,
        automaticallyFitsLargeSurfaces: Bool = true
    ) {
        self.id = id
        self.name = name
        self.ghosts = ghosts
        self.windowMode = windowMode
        self.shellPercent = shellPercent
        self.balloonPercent = balloonPercent
        self.textPercent = textPercent
        self.linksBalloonScale = linksBalloonScale
        self.automaticallyFitsLargeSurfaces = automaticallyFitsLargeSurfaces
    }
}

@MainActor
public final class LayoutPresetStore: ObservableObject {
    @Published public private(set) var presets: [LayoutPreset]
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "utatane.layout-presets.v1") {
        self.defaults = defaults
        self.key = key
        presets = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([LayoutPreset].self, from: $0) } ?? []
    }

    public func save(_ preset: LayoutPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist()
    }

    public func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
        persist()
    }

    public func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: key)
    }
}
