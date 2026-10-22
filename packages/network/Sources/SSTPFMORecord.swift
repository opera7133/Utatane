import CryptoKit
import Foundation

/// Portable FMO fields. Windows HWNDs and shared-memory objects are intentionally absent.
public struct SSTPFMORecord: Sendable {
    public let ghostDirectory: URL
    public let basewareDirectory: URL
    public let name: String
    public let partnerName: String
    public let fullName: String
    public let surfaces: [Int: Int]

    public init(
        ghostDirectory: URL, basewareDirectory: URL,
        name: String, partnerName: String, fullName: String, surfaces: [Int: Int]
    ) {
        self.ghostDirectory = ghostDirectory
        self.basewareDirectory = basewareDirectory
        self.name = name
        self.partnerName = partnerName
        self.fullName = fullName
        self.surfaces = surfaces
    }

    public static func identifier(for ghostDirectory: URL) -> String {
        SHA256.hash(data: Data(ghostDirectory.standardizedFileURL.path.utf8))
            .prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public static func serialize(_ records: [Self]) -> String {
        records.map { record in
            let id = identifier(for: record.ghostDirectory)
            var fields = [
                ("path", record.basewareDirectory.standardizedFileURL.path + "/"),
                ("name", record.name), ("keroname", record.partnerName),
                ("ghostpath", record.ghostDirectory.standardizedFileURL.path + "/"),
                ("fullname", record.fullName)
            ]
            for (scope, key) in [(0, "sakura.surface"), (1, "kero.surface")] {
                if let surface = record.surfaces[scope] {
                    fields.append((key, String(surface)))
                }
            }
            return fields.map { key, value in
                let cleaned = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                return "\(id).\(key)\u{1}\(String(String.UnicodeScalarView(cleaned)))"
            }.joined(separator: "\r\n")
        }.joined(separator: "\r\n")
    }
}
