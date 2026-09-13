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
    /// Re-validates every manifest entry and replaces missing or mismatched files.
    /// Network updates already compare every file, so repair shares the same
    /// transactional implementation while remaining a distinct user intent.
    case repair
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
        case .update, .repair:
            try await updater.update(
                rootDirectory: target.rootDirectory,
                homeURL: target.homeURL,
                progress: progress
            )
        }
    }
}

public struct ContentUpdateBatchItemResult: Sendable, Equatable {
    public let target: ContentUpdateTarget
    public let result: ContentUpdateResult?
    public let failureDescription: String?
    public let attempts: Int

    public var succeeded: Bool {
        result != nil
    }

    public init(
        target: ContentUpdateTarget,
        result: ContentUpdateResult?,
        failureDescription: String?,
        attempts: Int
    ) {
        self.target = target
        self.result = result
        self.failureDescription = failureDescription
        self.attempts = attempts
    }
}

public struct ContentUpdateBatchResult: Sendable, Equatable {
    public let items: [ContentUpdateBatchItemResult]

    public init(items: [ContentUpdateBatchItemResult]) {
        self.items = items
    }

    public var succeededCount: Int {
        items.count(where: \.succeeded)
    }

    public var failedCount: Int {
        items.count - succeededCount
    }
}

public enum ContentUpdateBatchProgress: Sendable, Equatable {
    case targetBegin(target: ContentUpdateTarget, index: Int, total: Int, attempt: Int)
    case targetProgress(target: ContentUpdateTarget, progress: ContentUpdateProgress)
    case targetRetry(target: ContentUpdateTarget, attempt: Int, failureDescription: String)
    case targetComplete(target: ContentUpdateTarget, result: ContentUpdateResult, attempts: Int)
    case targetFailure(target: ContentUpdateTarget, attempts: Int, failureDescription: String)
}

public struct ContentUpdateBatchJob: Sendable {
    public typealias Progress = @MainActor @Sendable (ContentUpdateBatchProgress) async -> Void

    private let job: ContentUpdateJob

    public init(job: ContentUpdateJob = ContentUpdateJob()) {
        self.job = job
    }

    /// Runs targets in catalog order. A failed target does not prevent the next
    /// independent content package from updating; cancellation stops the batch.
    public func run(
        targets: [ContentUpdateTarget],
        operation: ContentUpdateOperation,
        maximumAttempts: Int = 2,
        progress: Progress? = nil
    ) async throws -> ContentUpdateBatchResult {
        let attemptLimit = max(1, maximumAttempts)
        var items: [ContentUpdateBatchItemResult] = []
        for (index, target) in targets.enumerated() {
            try Task.checkCancellation()
            var attempt = 0
            while true {
                attempt += 1
                await progress?(.targetBegin(
                    target: target,
                    index: index,
                    total: targets.count,
                    attempt: attempt
                ))
                do {
                    let result = try await job.run(
                        target: target,
                        operation: operation,
                        progress: { itemProgress in
                            await progress?(.targetProgress(target: target, progress: itemProgress))
                        }
                    )
                    items.append(ContentUpdateBatchItemResult(
                        target: target,
                        result: result,
                        failureDescription: nil,
                        attempts: attempt
                    ))
                    await progress?(.targetComplete(target: target, result: result, attempts: attempt))
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let failureDescription = error.localizedDescription
                    if attempt < attemptLimit, Self.isRetryable(error) {
                        await progress?(.targetRetry(
                            target: target,
                            attempt: attempt + 1,
                            failureDescription: failureDescription
                        ))
                        continue
                    }
                    items.append(ContentUpdateBatchItemResult(
                        target: target,
                        result: nil,
                        failureDescription: failureDescription,
                        attempts: attempt
                    ))
                    await progress?(.targetFailure(
                        target: target,
                        attempts: attempt,
                        failureDescription: failureDescription
                    ))
                    break
                }
            }
        }
        return ContentUpdateBatchResult(items: items)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case ContentNetworkUpdateError.checksumMismatch,
             ContentNetworkUpdateError.downloadFailed:
            true
        default:
            false
        }
    }
}
