import AppKit
import CoreImage
import Testing
@testable import UtatanePlatformMacOS
import UtataneShell

@MainActor
struct SpeechHistoryMemoryTests {
    private func entry(_ data: Data?, ghost: String = "a", id: UUID = UUID()) -> SpeechHistoryEntry {
        SpeechHistoryEntry(
            id: id, ghostIdentifier: ghost, ghostName: ghost, scope: 0,
            speakerName: "speaker", surfaceID: 0, thumbnailPNGData: data, text: "text"
        )
    }

    @Test
    func `equal thumbnails share storage across entries and ghosts`() throws {
        let history = SpeechHistoryStore(capacityPerGhost: 2)
        let png = try makePNG(width: 84, height: 84)
        for ghost in ["a", "b", "a", "a"] {
            let copy = png.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
            history.append(entry(copy, ghost: ghost))
        }
        #expect(history.entries.count == 3)
        #expect(history.uniqueThumbnailCount == 1)
        let buffers = Set(history.entries.compactMap {
            $0.thumbnailPNGData?.withUnsafeBytes { UInt(bitPattern: $0.baseAddress!) }
        })
        #expect(buffers.count == 1)
        history.clear(ghostIdentifier: "a")
        #expect(history.entries.map(\.ghostIdentifier) == ["b"])
        #expect(history.entries.first?.thumbnailPNGData == png)
        #expect(history.uniqueThumbnailCount == 1)
        history.clear(ghostIdentifier: "b")
        #expect(history.uniqueThumbnailCount == 0)
    }

    @Test
    func `thumbnail replacement trimming and clearing release unused bytes`() throws {
        let history = SpeechHistoryStore(capacityPerGhost: 1)
        let red = try makePNG(width: 84, height: 84, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
        let blue = try makePNG(width: 84, height: 84, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        #expect(red != blue)
        let initial = entry(red)
        history.upsert(initial)
        #expect(history.entries == [initial])
        // Text-only upserts must not accumulate extra references to the PNG.
        for _ in 0 ..< 10 {
            history.upsert(initial)
        }
        history.upsert(entry(blue, id: initial.id))
        #expect(history.entries.first?.thumbnailPNGData == blue)
        #expect(history.uniqueThumbnailCount == 1)
        history.append(entry(red, ghost: "b"))
        #expect(history.uniqueThumbnailCount == 2) // Same surface ID, different pixels.
        history.append(entry(nil)) // Trims the blue entry in ghost a.
        #expect(history.uniqueThumbnailCount == 1)
        let remainingID = try #require(history.entries(for: "b").first?.id)
        history.upsert(entry(nil, ghost: "b", id: remainingID))
        #expect(history.uniqueThumbnailCount == 0)
        history.append(entry(red))
        history.clear()
        #expect(history.entries.isEmpty)
        #expect(history.uniqueThumbnailCount == 0)
    }

    @Test
    func `decoded thumbnails are reused and released with their view cache`() throws {
        let png = try makePNG(width: 84, height: 84)
        weak var decoded: NSImage?
        try autoreleasepool {
            let cache = SpeechHistoryThumbnailCache()
            let first = try #require(cache.image(for: png))
            decoded = first
            let copy = png.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
            #expect(cache.image(for: copy) === first)
            #expect(cache.image(for: nil) == nil)
            #expect(cache.image(for: Data([0, 1, 2])) == nil)
        }
        #expect(decoded == nil)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_HISTORY_SHELL"] != nil)) @MainActor
func `inspect history thumbnails from a real shell`() throws {
    let path = try #require(ProcessInfo.processInfo.environment["UTATANE_HISTORY_SHELL"])
    let root = URL(filePath: path)
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    defer { surfaces.resetContent() }
    try surfaces.show(shell: ShellLoader().load(from: root), scope: 0, surfaceID: 0)
    let data = try #require(surfaces.speechHistoryThumbnailPNGData(for: 0))
    if let output = ProcessInfo.processInfo.environment["UTATANE_HISTORY_THUMBNAIL_OUTPUT"] {
        try data.write(to: URL(filePath: output))
    }
    let bitmap = try #require(NSBitmapImageRep(data: data))
    let visible = (0 ..< bitmap.pixelsHigh).reduce(0) { count, y in
        count + (0 ..< bitmap.pixelsWide).filter { bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0 > 0.1 }.count
    }
    print("THUMBNAIL alpha pixels \(visible) / \(bitmap.pixelsWide * bitmap.pixelsHigh)")
    #expect(visible > 100)
}

@Test @MainActor
func `history thumbnails convert floating point composited images to visible RGBA`() throws {
    let rect = CGRect(x: 0, y: 0, width: 20, height: 40)
    let source = CIImage(color: CIColor(red: 1, green: 0.25, blue: 0, alpha: 1)).cropped(to: rect)
    let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let cgImage = try #require(CIContext().createCGImage(source, from: rect, format: .RGBAh, colorSpace: space))
    let image = NSImage(cgImage: cgImage, size: rect.size)
    let data = try #require(SpeechHistoryThumbnail.pngData(from: image))
    let thumbnail = try #require(NSBitmapImageRep(data: data))
    #expect(thumbnail.pixelsWide == 64)
    #expect(thumbnail.pixelsHigh == 64)
    let center = try #require(thumbnail.colorAt(x: 32, y: 32)?.usingColorSpace(.deviceRGB))
    #expect(center.alphaComponent > 0.99)
    #expect(center.redComponent > 0.9)
    #expect(center.blueComponent < 0.1)
}
