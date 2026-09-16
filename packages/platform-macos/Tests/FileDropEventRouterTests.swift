import Foundation
import Testing
@testable import UtatanePlatformMacOS

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
