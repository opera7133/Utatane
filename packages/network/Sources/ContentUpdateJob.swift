import Foundation

public struct ContentUpdateTarget: Sendable, Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case ghost
        case shell
        case balloon
        case headline
        case plugin
    }

    public let kind: Kind
    public let name: String
    public let rootDirectory: URL
    public let homeURL: URL

    public init(kind: Kind, name: String, rootDirectory: URL, homeURL: URL) {
        self.kind = kind
        self.name = name
        self.rootDirectory = rootDirectory
        self.homeURL = homeURL
    }

    public var id: String {
        "\(kind.rawValue):\(rootDirectory.standardizedFileURL.path)"
    }
}

public enum ContentUpdateOperation: Sendable, Equatable {
    case check
    case update
}

public struct ContentUpdateJob: Sendable {
    private let updater: ContentNetworkUpdater

    public init(updater: ContentNetworkUpdater = ContentNetworkUpdater()) {
        self.updater = updater
    }

    public func run(
        target: ContentUpdateTarget,
        operation: ContentUpdateOperation,
        progress: ContentNetworkUpdater.Progress? = nil
    ) async throws -> ContentUpdateResult {
        try Task.checkCancellation()
        return switch operation {
        case .check:
            try await updater.check(
                rootDirectory: target.rootDirectory,
                homeURL: target.homeURL
            )
        case .update:
            try await updater.update(
                rootDirectory: target.rootDirectory,
                homeURL: target.homeURL,
                progress: progress
            )
        }
    }
}
