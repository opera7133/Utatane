import Foundation
import OSLog

public enum LogLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    public var title: String {
        switch self {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERROR"
        }
    }

    public var icon: String {
        switch self {
        case .debug: "text.alignleft"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var priority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String
    public let details: String?
    public let ghostName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: String,
        message: String,
        details: String? = nil,
        ghostName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
        self.ghostName = ghostName
    }
}

public final class AppLogStore: ObservableObject, @unchecked Sendable {
    public static let shared = AppLogStore()

    /// UI snapshot, refreshed explicitly by a visible console rather than by each log call.
    @MainActor @Published public private(set) var entries: [LogEntry] = []

    private let lock = NSLock()
    private var buffer: [LogEntry?]
    private var oldestIndex = 0
    private var entryCount = 0
    private var needsPublication = false
    public let maxEntries: Int

    public init(maxEntries: Int = 2000) {
        self.maxEntries = max(0, maxEntries)
        buffer = Array(repeating: nil, count: max(0, maxEntries))
    }

    public func log(
        level: LogLevel,
        category: String,
        message: String,
        details: String? = nil,
        ghostName: String? = nil
    ) {
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            details: details,
            ghostName: ghostName
        )

        lock.withLock {
            guard maxEntries > 0 else { return }
            buffer[(oldestIndex + entryCount) % maxEntries] = entry
            if entryCount == maxEntries {
                oldestIndex = (oldestIndex + 1) % maxEntries
            } else {
                entryCount += 1
            }
            needsPublication = true
        }

        emitOSLog(entry: entry)
    }

    public func debug(_ message: String, category: String = "App", details: String? = nil, ghostName: String? = nil) {
        log(level: .debug, category: category, message: message, details: details, ghostName: ghostName)
    }

    public func info(_ message: String, category: String = "App", details: String? = nil, ghostName: String? = nil) {
        log(level: .info, category: category, message: message, details: details, ghostName: ghostName)
    }

    public func warning(_ message: String, category: String = "App", details: String? = nil, ghostName: String? = nil) {
        log(level: .warning, category: category, message: message, details: details, ghostName: ghostName)
    }

    public func error(_ message: String, category: String = "App", details: String? = nil, ghostName: String? = nil) {
        log(level: .error, category: category, message: message, details: details, ghostName: ghostName)
    }

    public func clear() {
        lock.withLock {
            buffer = Array(repeating: nil, count: maxEntries)
            oldestIndex = 0
            entryCount = 0
            needsPublication = true
        }
    }

    /// Read the current history independently of whether the console is visible.
    public func snapshot() -> [LogEntry] {
        lock.withLock { orderedEntries() }
    }

    /// Coalesce all writes since the previous refresh into a single UI update.
    @MainActor
    public func publishSnapshot() {
        let snapshot: [LogEntry]? = lock.withLock {
            guard needsPublication else { return nil }
            needsPublication = false
            return orderedEntries()
        }
        if let snapshot {
            entries = snapshot
        }
    }

    /// Release the UI's retained history while keeping the actual log buffer intact.
    @MainActor
    public func discardPublishedSnapshot() {
        lock.withLock { needsPublication = true }
        if !entries.isEmpty {
            entries = []
        }
    }

    /// Must be called with lock held. The result never shares the ring's array storage.
    private func orderedEntries() -> [LogEntry] {
        (0 ..< entryCount).map { buffer[(oldestIndex + $0) % maxEntries]! }
    }

    public static func formatText(for entries: [LogEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return entries.map { entry in
            let ghostTag = entry.ghostName.map { " [\($0)]" } ?? ""
            var text = "[\(formatter.string(from: entry.timestamp))] [\(entry.level.title)] [\(entry.category)]\(ghostTag) \(entry.message)"
            if let details = entry.details, !details.isEmpty {
                text += "\n  Details:\n" + details.split(separator: "\n").map { "    " + $0 }.joined(separator: "\n")
            }
            return text
        }.joined(separator: "\n")
    }

    private func emitOSLog(entry: LogEntry) {
        let logger = Logger(subsystem: "dev.utatane.app", category: entry.category)
        let ghostTag = entry.ghostName.map { "[\($0)] " } ?? ""
        let fullMessage = "\(ghostTag)\(entry.message)\(entry.details.map { "\n\($0)" } ?? "")"

        switch entry.level {
        case .debug:
            logger.debug("\(fullMessage, privacy: .public)")
        case .info:
            logger.info("\(fullMessage, privacy: .public)")
        case .warning:
            logger.warning("\(fullMessage, privacy: .public)")
        case .error:
            logger.error("\(fullMessage, privacy: .public)")
        }
    }
}
