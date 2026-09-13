import Foundation

public enum SafeContentTrashError: LocalizedError, Equatable {
    case missingItem
    case unsafeLocation

    public var errorDescription: String? {
        switch self {
        case .missingItem:
            String(localized: "削除するコンテンツが見つからない。")
        case .unsafeLocation:
            String(localized: "コンテンツの保存場所を安全に確認できないため、削除しなかった。")
        }
    }
}

public struct SafeContentTrash {
    private let fileManager: FileManager
    private let moveItem: (URL) throws -> Void

    public init(
        fileManager: FileManager = .default,
        moveItem: ((URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.moveItem = moveItem ?? { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    public static func isDirectChild(_ itemURL: URL, of containerURL: URL) -> Bool {
        let item = itemURL.standardizedFileURL.resolvingSymlinksInPath()
        let container = containerURL.standardizedFileURL.resolvingSymlinksInPath()
        return item != container && item.deletingLastPathComponent() == container
    }

    public func moveToTrash(_ itemURL: URL, directChildOf containerURL: URL) throws {
        guard fileManager.fileExists(atPath: itemURL.path) else {
            throw SafeContentTrashError.missingItem
        }
        guard Self.isDirectChild(itemURL, of: containerURL) else {
            throw SafeContentTrashError.unsafeLocation
        }
        try moveItem(itemURL.standardizedFileURL)
    }
}
