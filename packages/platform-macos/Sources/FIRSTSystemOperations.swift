import AppKit
import Darwin

public enum FIRSTSystemOperation: String, Sendable, CaseIterable {
    case shutdown
    case restart
    case clearRecentDocuments
    case refreshMemory

    /// Fixed source only: ghost text never becomes AppleScript code.
    public var appleScriptSource: String? {
        switch self {
        case .shutdown: "tell application \"System Events\" to shut down"
        case .restart: "tell application \"System Events\" to restart"
        default: nil
        }
    }
}

public enum FIRSTSystemOperationError: LocalizedError {
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .executionFailed(message): message
        }
    }
}

@MainActor
public struct FIRSTSystemOperations {
    public init() {}

    public func perform(_ operation: FIRSTSystemOperation) throws {
        if let source = operation.appleScriptSource {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw FIRSTSystemOperationError.executionFailed("終了・再起動の要求を作成できなかった")
            }
            script.executeAndReturnError(&error)
            if let error {
                throw FIRSTSystemOperationError.executionFailed(error.description)
            }
            return
        }
        switch operation {
        case .clearRecentDocuments:
            NSDocumentController.shared.clearRecentDocuments(nil)
        case .refreshMemory:
            // Release unused pages in this process, matching FIRST's original
            // working-set operation without invoking a privileged system purge.
            _ = malloc_zone_pressure_relief(nil, 0)
        case .shutdown, .restart:
            break
        }
    }
}
