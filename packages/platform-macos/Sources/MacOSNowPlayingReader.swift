import Foundation

public struct NowPlayingTrack: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let source: String?
    public let duration: Double?
    public let uniqueIdentifier: String?
    public let isPlaying: Bool

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        source: String? = nil,
        duration: Double? = nil,
        uniqueIdentifier: String? = nil,
        isPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.duration = duration
        self.uniqueIdentifier = uniqueIdentifier
        self.isPlaying = isPlaying
    }

    public var sspExtendedReferences: [Int: String] {
        var references = [0: title, 1: artist]
        let separator = "\u{01}"
        var extendedValues: [(String, String)] = []
        if let album, !album.isEmpty {
            extendedValues.append(("album", album))
        }
        if let source, !source.isEmpty {
            extendedValues.append(("source", source))
        }
        if let duration, duration.isFinite, duration >= 0 {
            extendedValues.append(("duration", String(Int(duration.rounded()))))
        }
        if let uniqueIdentifier, !uniqueIdentifier.isEmpty {
            extendedValues.append(("uniqueid", uniqueIdentifier))
        }
        for (offset, value) in extendedValues.enumerated() {
            references[offset + 2] = value.0 + separator + value.1
        }
        return references
    }

    fileprivate var eventIdentity: String {
        [uniqueIdentifier, source, title, artist, album]
            .compactMap(\.self)
            .joined(separator: "\u{1F}")
    }
}

public struct NowPlayingChangeDetector: Sendable {
    private var lastIdentity: String?

    public init() {}

    public mutating func consume(_ track: NowPlayingTrack?) -> NowPlayingTrack? {
        guard let track, track.isPlaying, !track.title.isEmpty else {
            lastIdentity = nil
            return nil
        }
        guard track.eventIdentity != lastIdentity else { return nil }
        lastIdentity = track.eventIdentity
        return track
    }
}

public struct MacOSNowPlayingReader: Sendable {
    private let executableURL: URL

    public init(executableURL: URL = URL(filePath: "/usr/bin/osascript")) {
        self.executableURL = executableURL
    }

    public func currentTrack() async throws -> NowPlayingTrack? {
        let executableURL = executableURL
        return try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = executableURL
            process.arguments = ["-l", "JavaScript", "-e", Self.script]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = error
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let details = String(
                    data: error.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw NowPlayingReadError.commandFailed(details.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard !data.isEmpty else { return nil }
            return try JSONDecoder().decode(NowPlayingTrack?.self, from: data)
        }.value
    }

    private static let script = #"""
    ObjC.import('Foundation');

    function value(dictionary, key) {
      const raw = dictionary.valueForKey(key);
      if (!raw) return null;
      const unwrapped = ObjC.unwrap(raw);
      return unwrapped === undefined ? null : unwrapped;
    }

    function mediaRemoteTrack() {
      try {
        const framework = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
        if (!framework || !framework.load) return null;
        const request = $.NSClassFromString('MRNowPlayingRequest');
        if (!request) return null;
        const item = request.localNowPlayingItem;
        const info = item && item.nowPlayingInfo;
        if (!info) return null;
        const title = value(info, 'kMRMediaRemoteNowPlayingInfoTitle');
        if (!title) return null;
        const playerPath = request.localNowPlayingPlayerPath;
        const client = playerPath && playerPath.client;
        const source = client && client.displayName ? ObjC.unwrap(client.displayName) : null;
        const playbackRate = value(info, 'kMRMediaRemoteNowPlayingInfoPlaybackRate');
        return {
          title: String(title),
          artist: String(value(info, 'kMRMediaRemoteNowPlayingInfoArtist') || ''),
          album: value(info, 'kMRMediaRemoteNowPlayingInfoAlbum'),
          source: source,
          duration: value(info, 'kMRMediaRemoteNowPlayingInfoDuration'),
          uniqueIdentifier: value(info, 'kMRMediaRemoteNowPlayingInfoUniqueIdentifier'),
          isPlaying: playbackRate === null ? true : Number(playbackRate) > 0
        };
      } catch (_) {
        return null;
      }
    }

    function scriptedPlayerTrack(name) {
      try {
        const app = Application(name);
        if (!app.running()) return null;
        const state = String(app.playerState());
        if (state.toLowerCase().indexOf('playing') < 0) return null;
        const track = app.currentTrack;
        return {
          title: String(track.name() || ''),
          artist: String(track.artist() || ''),
          album: String(track.album() || ''),
          source: name,
          duration: Number(track.duration() || 0),
          uniqueIdentifier: null,
          isPlaying: true
        };
      } catch (_) {
        return null;
      }
    }

    function run() {
      const track = mediaRemoteTrack() || scriptedPlayerTrack('Spotify') || scriptedPlayerTrack('Music');
      return JSON.stringify(track);
    }
    """#
}

public enum NowPlayingReadError: LocalizedError, Equatable {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(details):
            details.isEmpty ? "再生中の曲情報を取得できませんでした。" : details
        }
    }
}
