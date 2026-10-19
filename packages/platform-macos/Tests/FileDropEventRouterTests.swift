import Foundation
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneRuntime
import UtataneSakuraScript

@MainActor
@Test(arguments: ["OnFileDrop2", "OnFileDropEx", "OnFileDrop", "unhandled"])
func `file drop falls back to legacy events without importing twice`(handledID: String) async throws {
    let urls = [URL(filePath: "/tmp/first song.mp3"), URL(filePath: "/tmp/二曲目.wav")]
    var events: [GhostEvent] = []
    let responses = try await FileDropEventRouter.responses(scope: 1, urls: urls) { event in
        events.append(event)
        guard case let .shiori(id, _) = event, id == handledID else {
            return PersonalityResponse(script: nil)
        }
        return PersonalityResponse(script: SakuraScript(rawValue: #"\e"#))
    }
    let expectedIDs: [String] = switch handledID {
    case "OnFileDrop2": ["OnFileDrop2"]
    case "OnFileDropEx": ["OnFileDrop2", "OnFileDropEx"]
    default: ["OnFileDrop2", "OnFileDropEx", "OnFileDrop", "OnFileDrop"]
    }
    #expect(events.compactMap { event -> String? in
        guard case let .shiori(id, _) = event else { return nil }
        return id
    } == expectedIDs)
    #expect(responses.count == (handledID == "unhandled" ? 0 : handledID == "OnFileDrop" ? 2 : 1))
    if handledID == "OnFileDrop" {
        #expect(events[2] == .shiori(id: "OnFileDrop", references: [0: urls[0].path, 1: "1", 2: "audio/mpeg"]))
        #expect(events[3] == .shiori(id: "OnFileDrop", references: [0: urls[1].path, 1: "1", 2: FileDropEventRouter.mimeType(urls[1])]))
    }
}

@Test func `file drop events preserve path scope and MIME order`() {
    let image = URL(fileURLWithPath: "/tmp/picture.png")
    let audio = URL(fileURLWithPath: "/tmp/sound.mp3")
    #expect(FileDropEventRouter.dropping(scope: 2, urls: [image, audio]) == .shiori(
        id: "OnFileDropping",
        references: [0: image.path, 1: "2"]
    ))
    #expect(FileDropEventRouter.dropped(scope: 2, urls: [image, audio]) == .shiori(
        id: "OnFileDrop2",
        references: [
            0: "\(image.path)\u{1}\(audio.path)",
            1: "2",
            2: "image/png\u{1}audio/mpeg"
        ]
    ))
}

@Test func `directory drops generate one event per directory`() {
    let first = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
    let file = URL(fileURLWithPath: "/tmp/file.txt")
    let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)
    #expect(FileDropEventRouter.directoryEvents(scope: 1, urls: [first, file, second]) == [
        .shiori(id: "OnDirectoryDrop", references: [0: first.path, 1: "1"]),
        .shiori(id: "OnDirectoryDrop", references: [0: second.path, 1: "1"])
    ])
    #expect(FileDropEventRouter.mimeType(first) == "inode/directory")
}

@Test func `viewer events follow the dropped file type and exclude NAR installation`() {
    let image = URL(fileURLWithPath: "/tmp/picture.webp")
    let audio = URL(fileURLWithPath: "/tmp/sound.wav")
    let movie = URL(fileURLWithPath: "/tmp/movie.mp4")
    let archive = URL(fileURLWithPath: "/tmp/files.zip")
    let nar = URL(fileURLWithPath: "/tmp/ghost.nar")
    #expect(FileDropEventRouter.viewerEventID(image) == "OnPictureViewerOpen")
    #expect(FileDropEventRouter.viewerEventID(audio) == "OnMediaPlayerOpen")
    #expect(FileDropEventRouter.viewerEventID(movie) == "OnMediaPlayerOpen")
    #expect(FileDropEventRouter.viewerEventID(archive) == "OnArchiveViewerOpen")
    #expect(FileDropEventRouter.viewerOpened(scope: 0, urls: [nar]) == nil)
    #expect(FileDropEventRouter.viewerOpened(scope: 0, urls: [archive]) == .shiori(
        id: "OnArchiveViewerOpen",
        references: [0: archive.path, 1: "0", 2: "application/zip"]
    ))
}
