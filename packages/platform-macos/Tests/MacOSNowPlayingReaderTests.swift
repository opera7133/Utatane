import Testing
@testable import UtatanePlatformMacOS

@Test func `extended references follow SSP music play format`() {
    let track = NowPlayingTrack(
        title: "Song",
        artist: "Artist",
        album: "Album",
        source: "Spotify",
        duration: 183.6,
        uniqueIdentifier: "spotify:track:1",
        isPlaying: true
    )

    #expect(track.sspExtendedReferences == [
        0: "Song",
        1: "Artist",
        2: "album\u{01}Album",
        3: "source\u{01}Spotify",
        4: "duration\u{01}184",
        5: "uniqueid\u{01}spotify:track:1"
    ])
}

@Test func `change detector emits once per playing track`() {
    var detector = NowPlayingChangeDetector()
    let first = NowPlayingTrack(title: "One", artist: "Artist", isPlaying: true)
    let paused = NowPlayingTrack(title: "One", artist: "Artist", isPlaying: false)
    let second = NowPlayingTrack(title: "Two", artist: "Artist", isPlaying: true)

    #expect(detector.consume(first) == first)
    #expect(detector.consume(first) == nil)
    #expect(detector.consume(paused) == nil)
    #expect(detector.consume(first) == first)
    #expect(detector.consume(second) == second)
}
