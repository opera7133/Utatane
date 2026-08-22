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

    @MainActor @Published public private(set) var entries: [LogEntry] = []

    private let lock = NSLock()
    private var internalEntries: [LogEntry] = []
    public let maxEntries: Int

    public init(maxEntries: Int = 2000) {
        self.maxEntries = maxEntries
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

        lock.lock()
        internalEntries.append(entry)
        if internalEntries.count > maxEntries {
            internalEntries.removeFirst(internalEntries.count - maxEntries)
        }
        let snapshot = internalEntries
        lock.unlock()

        emitOSLog(entry: entry)

        Task { @MainActor in
            self.entries = snapshot
        }
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
        lock.lock()
        internalEntries.removeAll()
        lock.unlock()
        Task { @MainActor in
            self.entries = []
        }
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
