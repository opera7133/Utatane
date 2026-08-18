import Foundation

public enum BalloonError: LocalizedError, Equatable {
    case missingFile(URL)
    case unsupportedTextEncoding(URL)
    case invalidType(URL)
    case missingImage(speaker: String, style: Int, directory: URL)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            "必要なファイルがない: \(url.path)"
        case let .unsupportedTextEncoding(url):
            "文字コードを判定できない: \(url.path)"
        case let .invalidType(url):
            "バルーンではない: \(url.path)"
        case let .missingImage(speaker, style, directory):
            "\(speaker)側のballoon\(style)画像が見つからない: \(directory.path)"
        }
    }
}

public struct BalloonLoader: Sendable {
    private let parser = BalloonDescriptParser()

    public init() {}

    public func loadInstalled(from rootDirectory: URL) throws -> [BalloonDefinition] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? load(from: directory)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func load(from directory: URL) throws -> BalloonDefinition {
        let descriptURL = directory.appending(path: "descript.txt", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: descriptURL.path) else {
            throw BalloonError.missingFile(descriptURL)
        }

        let data = try Data(contentsOf: descriptURL)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .shiftJIS)
        else {
            throw BalloonError.unsupportedTextEncoding(descriptURL)
        }
        let values = parser.parse(text)
        guard values["type"]?.lowercased() == "balloon" else {
            throw BalloonError.invalidType(descriptURL)
        }

        return BalloonDefinition(
            directory: directory,
            name: values["name"] ?? directory.lastPathComponent,
            originX: integer("origin.x", in: values, default: 14),
            originY: integer("origin.y", in: values, default: 14),
            wordWrapPointX: integer("wordwrappoint.x", in: values, default: -14),
            wordWrapPointY: integer("wordwrappoint.y", in: values, default: 0),
            fontHeight: integer("font.height", in: values, default: 12),
            fontColor: BalloonColor(
                red: integer("font.color.r", in: values, default: 0),
                green: integer("font.color.g", in: values, default: 0),
                blue: integer("font.color.b", in: values, default: 0)
            ),
            arrow0X: integer("arrow0.x", in: values, default: 0),
            arrow0Y: integer("arrow0.y", in: values, default: 0),
            arrow1X: integer("arrow1.x", in: values, default: 0),
            arrow1Y: integer("arrow1.y", in: values, default: 0)
        )
    }

    public func arrowImageURL(index: Int, in balloon: BalloonDefinition) -> URL? {
        let url = balloon.directory.appending(
            path: "arrow\(index).png",
            directoryHint: .notDirectory
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func imageURL(
        speaker: BalloonSpeaker,
        style: Int = 0,
        in balloon: BalloonDefinition
    ) throws -> URL {
        let url = balloon.directory.appending(
            path: "balloon\(speaker.filenameMarker)\(style).png",
            directoryHint: .notDirectory
        )
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BalloonError.missingImage(
                speaker: speaker.filenameMarker,
                style: style,
                directory: balloon.directory
            )
        }
        return url
    }

    private func integer(
        _ key: String,
        in values: [String: String],
        default defaultValue: Int
    ) -> Int {
        values[key].flatMap(Int.init) ?? defaultValue
    }
}
