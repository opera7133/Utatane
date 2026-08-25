import CoreGraphics
import Foundation

public struct WindowLayoutEntry: Sendable, Equatable {
    public let ownerID: String
    public let characterName: String
    public let scope: Int
    public let frame: CGRect
    public let visibleScreenFrames: [CGRect]

    public init(
        ownerID: String,
        characterName: String,
        scope: Int,
        frame: CGRect,
        visibleScreenFrames: [CGRect]
    ) {
        self.ownerID = ownerID
        self.characterName = characterName
        self.scope = scope
        self.frame = frame
        self.visibleScreenFrames = visibleScreenFrames
    }
}

public struct WindowLayoutSnapshot: Sendable, Equatable {
    public let overlapsByOwner: [String: String]
    public let offscreenByOwner: [String: String]
    public let allOverlaps: String
    public let allOffscreen: String

    public init(entries: [WindowLayoutEntry]) {
        let separator = "\u{1}"
        let owners = Dictionary(grouping: entries, by: \WindowLayoutEntry.ownerID)
        overlapsByOwner = owners.mapValues { entries in
            Self.overlappingPairs(in: entries).map { "\($0.scope)-\($1.scope)" }.joined(separator: separator)
        }
        offscreenByOwner = owners.mapValues { entries in
            entries.filter(Self.isOffscreen).map { String($0.scope) }.sorted().joined(separator: separator)
        }
        allOverlaps = Self.overlappingPairs(in: entries).map {
            "\($0.characterName)/\($0.scope)-\($1.characterName)/\($1.scope)"
        }.joined(separator: separator)
        allOffscreen = entries.filter(Self.isOffscreen).map {
            "\($0.characterName)/\($0.scope)"
        }.sorted().joined(separator: separator)
    }

    private static func overlappingPairs(
        in entries: [WindowLayoutEntry]
    ) -> [(WindowLayoutEntry, WindowLayoutEntry)] {
        entries.indices.flatMap { firstIndex in
            entries.indices.compactMap { secondIndex in
                guard secondIndex > firstIndex,
                      entries[firstIndex].frame.intersects(entries[secondIndex].frame)
                else { return nil }
                return (entries[firstIndex], entries[secondIndex])
            }
        }
    }

    private static func isOffscreen(_ entry: WindowLayoutEntry) -> Bool {
        !entry.visibleScreenFrames.contains { $0.contains(entry.frame) }
    }
}
