import Foundation
import UniformTypeIdentifiers
import UtataneCore

public enum FileDropEventRouter {
    public static func dropping(scope: Int, urls: [URL]) -> GhostEvent? {
        guard let first = urls.first else { return nil }
        return .shiori(id: "OnFileDropping", references: [
            0: first.path,
            1: String(scope)
        ])
    }

    public static func directoryEvents(scope: Int, urls: [URL]) -> [GhostEvent] {
        urls.filter(\.hasDirectoryPath).map { url in
            .shiori(id: "OnDirectoryDrop", references: [
                0: url.path,
                1: String(scope)
            ])
        }
    }

    public static func dropped(scope: Int, urls: [URL]) -> GhostEvent? {
        guard !urls.isEmpty else { return nil }
        return .shiori(id: "OnFileDrop2", references: references(scope: scope, urls: urls))
    }

    public static func viewerOpened(scope: Int, urls: [URL]) -> GhostEvent? {
        guard let first = urls.first,
              first.pathExtension.caseInsensitiveCompare("nar") != .orderedSame,
              let eventID = viewerEventID(first)
        else {
            return nil
        }
        return .shiori(id: eventID, references: references(scope: scope, urls: urls))
    }

    public static func mimeType(_ url: URL) -> String {
        if url.hasDirectoryPath {
            return "inode/directory"
        }
        let fileExtension = url.pathExtension.lowercased()
        if let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType {
            return mimeType
        }
        return fallbackMIMETypes[fileExtension] ?? "application/octet-stream"
    }

    public static func viewerEventID(_ url: URL) -> String? {
        let fileExtension = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: fileExtension)
        if type?.conforms(to: .image) == true || imageExtensions.contains(fileExtension) {
            return "OnPictureViewerOpen"
        }
        if type?.conforms(to: .audio) == true || type?.conforms(to: .movie) == true
            || type?.conforms(to: .audiovisualContent) == true || mediaExtensions.contains(fileExtension)
        {
            return "OnMediaPlayerOpen"
        }
        if type?.conforms(to: .archive) == true || archiveExtensions.contains(fileExtension) {
            return "OnArchiveViewerOpen"
        }
        return nil
    }

    private static func references(scope: Int, urls: [URL]) -> [Int: String] {
        [
            0: urls.map(\.path).joined(separator: "\u{1}"),
            1: String(scope),
            2: urls.map(mimeType).joined(separator: "\u{1}")
        ]
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "avif"
    ]
    private static let mediaExtensions: Set<String> = [
        "wav", "mp3", "m4a", "aac", "flac", "ogg", "aiff", "mp4", "m4v", "mov", "avi", "mkv", "webm"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "lzh", "lha", "7z", "rar", "tar", "gz", "bz2", "xz"
    ]
    private static let fallbackMIMETypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "wav": "audio/wav",
        "mp3": "audio/mpeg",
        "mp4": "video/mp4",
        "mov": "video/quicktime",
        "zip": "application/zip",
        "tar": "application/x-tar",
        "gz": "application/gzip"
    ]
}
