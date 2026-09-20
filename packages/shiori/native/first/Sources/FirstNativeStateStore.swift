import Foundation

struct FirstTypingRecord: Codable, Equatable, Sendable {
    var correctCount: Int
    var totalMilliseconds: Int
}

struct FirstNativePersistentState: Codable, Equatable, Sendable {
    var energy: Int
    var lastBathDate: Date?
    var lastUpdateDate: Date? = nil
    var typingRecords: [FirstTypingRecord?]? = nil
}

struct FirstNativeStateStore: Sendable {
    private let fileURL: URL

    init(masterDirectoryURL: URL, stateRootURL: URL? = nil) {
        let identifier = Self.stableIdentifier(for: masterDirectoryURL.standardizedFileURL.path)
        let root = stateRootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Utatane/State/FIRST", directoryHint: .isDirectory)
        fileURL = root.appending(path: "\(identifier).json")
    }

    func load() -> FirstNativePersistentState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FirstNativePersistentState.self, from: data)
    }

    func save(_ state: FirstNativePersistentState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    private static func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
