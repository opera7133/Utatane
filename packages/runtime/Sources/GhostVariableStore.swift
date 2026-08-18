import Foundation

public actor GhostVariableStore {
    private let fileURL: URL
    private var values: [String: String] = [:]
    private var hasLoaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func value(forKey key: String) throws -> String? {
        try loadIfNeeded()
        return values[key]
    }

    public func setValue(_ value: String?, forKey key: String) throws {
        try loadIfNeeded()
        values[key] = value
        try persist()
    }

    public func snapshot() throws -> [String: String] {
        try loadIfNeeded()
        return values
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        values = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fileURL))
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: fileURL, options: .atomic)
    }
}
