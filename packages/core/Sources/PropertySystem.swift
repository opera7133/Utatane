import Foundation

public enum PropertySystemError: Error, Equatable, Sendable {
    case unknownProperty(String)
    case readOnlyProperty(String)
}

public struct PropertySystemConfiguration: Sendable, Equatable {
    public var basewareName: String
    public var basewareVersion: String
    public var values: [String: String]
    public var writableProperties: Set<String>

    public init(
        basewareName: String,
        basewareVersion: String,
        values: [String: String] = [:],
        writableProperties: Set<String> = []
    ) {
        self.basewareName = basewareName
        self.basewareVersion = basewareVersion
        self.values = values
        self.writableProperties = writableProperties
    }
}

/// Runtime storage and resolver for UKADOC's Property System.
///
/// Platform and ghost-specific layers register their snapshot values here, while
/// universally available system/baseware properties are resolved by this type.
public actor PropertySystem {
    private var values: [String: String]
    private var writableProperties: Set<String>
    private let basewareName: String
    private let basewareVersion: String
    private let now: @Sendable () -> Date

    public init(
        configuration: PropertySystemConfiguration,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        basewareName = configuration.basewareName
        basewareVersion = configuration.basewareVersion
        values = Self.normalized(configuration.values)
        writableProperties = Set(configuration.writableProperties.map(Self.normalize))
        self.now = now
    }

    public func value(for property: String) throws -> String {
        let key = Self.normalize(property)
        if let value = values[key] {
            return value
        }
        if let value = builtInValue(for: key) {
            return value
        }
        throw PropertySystemError.unknownProperty(property)
    }

    public func values(for properties: [String]) -> [String] {
        properties.map { (try? value(for: $0)) ?? "" }
    }

    public func setValue(_ value: String, for property: String) throws {
        let key = Self.normalize(property)
        guard writableProperties.contains(key) else {
            throw PropertySystemError.readOnlyProperty(property)
        }
        values[key] = value
    }

    public func register(values newValues: [String: String], writable: Set<String> = []) {
        values.merge(Self.normalized(newValues)) { _, new in new }
        writableProperties.formUnion(writable.map(Self.normalize))
    }

    private func builtInValue(for property: String) -> String? {
        let calendar = Calendar.current
        let date = now()
        switch property {
        case "system.year": return String(calendar.component(.year, from: date))
        case "system.month": return String(calendar.component(.month, from: date))
        case "system.day": return String(calendar.component(.day, from: date))
        case "system.hour": return String(calendar.component(.hour, from: date))
        case "system.minute": return String(calendar.component(.minute, from: date))
        case "system.second": return String(calendar.component(.second, from: date))
        case "system.millisecond": return String(calendar.component(.nanosecond, from: date) / 1_000_000)
        case "system.dayofweek": return String(calendar.component(.weekday, from: date) - 1)
        case "system.os": return "macOS"
        case "system.cpu": return ProcessInfo.processInfo.processorCount.description
        case "system.memory": return ProcessInfo.processInfo.physicalMemory.description
        case "baseware.name": return basewareName
        case "baseware.version": return basewareVersion
        default: return nil
        }
    }

    private static func normalize(_ property: String) -> String {
        property.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalized(_ values: [String: String]) -> [String: String] {
        Dictionary(values.map { (normalize($0.key), $0.value) }, uniquingKeysWith: { _, new in new })
    }
}
