import Foundation

public struct GhostSiteMenuEntry: Equatable, Sendable {
    public let title: String
    public let target: String
    public let banner: String
    public let selectionScript: String

    public init(title: String, target: String, banner: String = "", selectionScript: String = "") {
        self.title = title
        self.target = target
        self.banner = banner
        self.selectionScript = selectionScript
    }
}

public struct GhostSiteMenuParser: Sendable {
    public init() {}

    public func parse(_ value: String?) -> [GhostSiteMenuEntry] {
        guard let value, !value.isEmpty else { return [] }
        return value.components(separatedBy: "\u{2}").compactMap { row in
            let fields = row.components(separatedBy: "\u{1}")
            guard fields.count >= 2,
                  !fields[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !fields[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return GhostSiteMenuEntry(
                title: fields[0],
                target: fields[1],
                banner: fields.indices.contains(2) ? fields[2] : "",
                selectionScript: fields.indices.contains(3) ? fields[3] : ""
            )
        }
    }
}
