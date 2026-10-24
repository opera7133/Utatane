import Foundation

/// Explicit dependencies supplement detection of bundled DLLs. Nothing is
/// downloaded or executed while reading this optional creator-authored file.
public struct GhostModuleDeclaration: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public let id: String
        public let kind: String
    }

    public let schemaVersion: Int
    public let modules: [Entry]
    public enum Failure: Error { case invalidDeclaration }

    public static func read(from master: URL) throws -> Self? {
        let path = master.appending(path: "utatane-modules.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path, options: .mappedIfSafe)
        guard data.count <= 65536, let result = try? JSONDecoder().decode(Self.self, from: data),
              result.schemaVersion == 1, result.modules.count <= 128,
              result.modules.allSatisfy({ entry in
                  validID(entry.id) && ["shiori", "saori"].contains(entry.kind)
              }), Set(result.modules.map(\.id)).count == result.modules.count else { throw Failure.invalidDeclaration }
        return result
    }

    static func validID(_ id: String) -> Bool {
        guard let first = id.utf8.first, (97 ... 122).contains(first), id.utf8.count <= 128 else { return false }
        return id.utf8.allSatisfy { (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 45 || $0 == 46 }
    }
}
