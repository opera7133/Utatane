import AVFoundation
import Foundation
import ImageIO
import UtataneNativeSaori

/// Reads metadata without creating a player or changing playback state.
public struct MacOSMediaInfoReader: InternalSaoriMediaReading {
    public init() {}

    public func read(_ url: URL) throws -> InternalSaoriMediaInfo {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        {
            return .init(kind: "image", values: ["width": width.stringValue, "height": height.stringValue])
        }
        // The SHIORI callback is synchronous. Run AVFoundation's async loading on
        // its own task; never depend on a callback running on the waiting thread.
        let result = MediaInfoResult()
        let task = Task.detached {
            let info = await Self.readAsset(url)
            result.finish(info)
        }
        guard result.ready.wait(timeout: .now() + 20) == .success else {
            task.cancel()
            throw CocoaError(.fileReadUnknown)
        }
        return result.value
    }

    private static func readAsset(_ url: URL) async -> InternalSaoriMediaInfo {
        let asset = AVURLAsset(url: url)
        do {
            let video = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            var values: [String: String] = [:]
            let kind: String
            if let track = video.first {
                let size = try await track.load(.naturalSize).applying(track.load(.preferredTransform))
                guard size.width.isFinite, size.height.isFinite,
                      abs(size.width) < Double(Int32.max), abs(size.height) < Double(Int32.max) else { return .init() }
                values["width"] = String(Int(abs(size.width).rounded()))
                values["height"] = String(Int(abs(size.height).rounded()))
                kind = "video"
            } else if !audio.isEmpty {
                kind = "audio"
            } else {
                return .init()
            }
            let duration = try await asset.load(.duration).seconds
            if duration.isFinite, duration >= 0, duration < Double(Int64.max) / 1000 {
                values["duration"] = String(Int64((duration * 1000).rounded()))
            }
            var collected: [String: [String]] = [:]
            let formats = try await asset.load(.availableMetadataFormats)
            var items = try await asset.load(.metadata)
            for format in formats {
                items += try await asset.loadMetadata(for: format)
            }
            for item in items {
                guard !Task.isCancelled, let key = metadataKey(item.identifier?.rawValue ?? "") else { continue }
                if let text = try? await item.load(.stringValue), !text.isEmpty {
                    if collected[key]?.contains(text) != true {
                        collected[key, default: []].append(text)
                    }
                } else if key == "track", let data = try? await item.load(.dataValue), data.count >= 4 {
                    let bytes = Array(data)
                    collected[key] = [String(Int(bytes[2]) * 256 + Int(bytes[3]))]
                }
            }
            for (key, texts) in collected {
                values[key] = texts.joined(separator: "; ")
            }
            if let year = values["year"] {
                let digits = String(year.prefix(4))
                values["year"] = digits.count == 4 && digits.utf8.allSatisfy { (48 ... 57).contains($0) } ? digits : ""
            }
            if let track = values["track"] {
                values["track"] = track.split(separator: "/").first.flatMap { Int($0) }.map(String.init) ?? ""
            }
            return .init(kind: kind, values: values)
        } catch { return .init() }
    }

    private static func metadataKey(_ identifier: String) -> String? {
        // AVFoundation escapes legacy iTunes four-character keys as %A9nam,
        // %A9ART, etc. These bytes are Latin-1 identifiers, not UTF-8 URLs.
        let leaf = (identifier.split(separator: "/").last.map(String.init)?.lowercased() ?? "")
            .replacingOccurrences(of: "%a9", with: "©")
        switch leaf {
        case "title", "tit2", "©nam": return "title"
        case "artist", "tpe1", "©art": return "artist"
        case "albumartist", "tpe2", "aart": return "albumartist"
        case "albumname", "talb", "©alb": return "album"
        case "type", "genre", "tcon", "©gen", "gnre": return "genre"
        case "description", "comment", "comm", "©cmt": return "comment"
        case "creationdate", "date", "year", "tyer", "tdrc", "©day": return "year"
        case "tracknumber", "trck", "trkn": return "track"
        default: return nil
        }
    }
}

private final class MediaInfoResult: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var info = InternalSaoriMediaInfo()
    var value: InternalSaoriMediaInfo {
        lock.withLock { info }
    }

    func finish(_ info: InternalSaoriMediaInfo) {
        lock.withLock { self.info = info }
        ready.signal()
    }
}
