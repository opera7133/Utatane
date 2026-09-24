import AppKit
import Testing
import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneShell

@Test @MainActor
func `dump preserves negative nested layers and crops only when requested`() throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for (file, size, color) in [("surface0.png", 8, NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)), ("base.png", 4, NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)), ("edge.png", 4, NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))] {
        try makePNG(width: size, height: size, color: color).write(to: directory.appending(path: file))
    }
    // Surface 1 extends left/up of its origin, then the bind moves it again.
    let definitions = SurfacesParser().parse("""
    surface0
    {
    animation0.interval,bind
    animation0.pattern0,overlay,1,0,-2,-1
    }
    surface1
    {
    element0,overlay,base.png,0,0
    element1,overlay,edge.png,-3,-2
    }
    """)
    let shell = ShellDefinition(directory: directory, surfaces: definitions, usesSelfAlpha: true, defaultBindGroups: [0: [0]])
    let controller = SurfaceWindowController(positionStore: positions)
    defer { controller.resetContent() }
    try controller.show(shell: shell, surfaceID: 0)
    let visibleSize = controller.renderedImage()?.size
    let output = directory.appending(path: "output")
    for cropped in [false, true] {
        let prefix = cropped ? "crop" : "full"
        #expect(try controller.dumpSurfaceImages(to: output, scope: 0, surfaceList: "0", prefix: prefix, cropsFromZero: cropped) == 1)
        let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf: output.appending(path: "\(prefix)0.png"))))
        if let path = ProcessInfo.processInfo.environment["UTATANE_LAYOUT_OUTPUT"] {
            let artifact = URL(filePath: path)
            try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
            try Data(contentsOf: output.appending(path: "\(prefix)0.png"))
                .write(to: artifact.appending(path: "\(prefix)0.png"))
        }
        #expect(bitmap.pixelsWide == (cropped ? 8 : 13))
        #expect(bitmap.pixelsHigh == (cropped ? 8 : 11))
        if cropped {
            let origin = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
            #expect(origin.greenComponent > 0.9 && origin.alphaComponent > 0.9)
        } else {
            let edge = try #require(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
            #expect(edge.redComponent > 0.9 && edge.alphaComponent > 0.9)
        }
        let corner = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1)?.usingColorSpace(.deviceRGB))
        #expect(corner.blueComponent > 0.9 && corner.alphaComponent > 0.9)
    }
    let canvas = SurfaceImageCanvas(image: NSImage(size: NSSize(width: 8, height: 8)))
    #expect(throws: SurfaceImageError.self) {
        try canvas.compositing(canvas, x: Int.max, y: 0, operation: .sourceOver,
                               clipsToBaseAlpha: false, expands: true, loader: SurfaceImageLoader())
    }
    // Expanded export must not pollute the normal, clipped display cache.
    try controller.changeSurface(to: 0)
    #expect(controller.renderedImage()?.size == visibleSize)
}

@Test @MainActor
func `balloon script offsets retain user drag after reset movement and reload`() throws {
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try makePNG(width: 120, height: 80).write(to: directory.appending(path: "balloons0.png"))
    let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    let geometry = MutablePresentationGeometryProvider(screens: [
        .init(frame: screen, visibleFrame: screen, bitsPerPixel: 32, scale: 1, isPrimary: true)
    ])
    let host = LayoutRecordingHost(geometry: geometry)
    let controller = BalloonWindowController(positionStore: positions, presentationHost: host)
    defer { controller.resetContent() }
    let surface = NSRect(x: 600, y: 400, width: 100, height: 200)
    let balloon = makeBalloon(directory: directory)
    try controller.show(balloon: balloon, text: "test", near: surface)
    let original = try #require(controller.windowFrame(for: 0)?.origin)
    let dragged = NSPoint(x: original.x + 35, y: original.y - 20)
    host.item?.setFrameOrigin(dragged, reason: .userInteraction)
    #expect(positions.balloonDragOffset(scope: 0, coordinateSpace: .desktop) == NSPoint(x: 35, y: -20))
    controller.setOffset(x: 50, y: 30, scope: 0)
    #expect(controller.windowFrame(for: 0)?.origin == NSPoint(x: dragged.x + 50, y: dragged.y - 30))
    controller.resetOffset(scope: 0)
    #expect(controller.windowFrame(for: 0)?.origin == dragged)
    controller.moveWithSurface(by: NSPoint(x: 10, y: 15), scope: 0, reason: .userInteraction)
    #expect(positions.balloonDragOffset(scope: 0, coordinateSpace: .desktop) == NSPoint(x: 35, y: -20))
    controller.resetContent()
    try controller.show(balloon: balloon, text: "again", near: surface)
    #expect(controller.windowFrame(for: 0)?.origin == dragged)
    controller.resetWindowPositions()
    #expect(controller.windowFrame(for: 0)?.origin == original)
    #expect(positions.balloonDragOffset(scope: 0, coordinateSpace: .desktop) == nil)
}

@MainActor
private final class LayoutRecordingHost: PresentationHosting {
    let host: DesktopPresentationHost
    var item: (any PresentationItem)?
    var geometryProvider: any PresentationGeometryProviding {
        host.geometryProvider
    }

    init(geometry: any PresentationGeometryProviding) {
        host = DesktopPresentationHost(geometryProvider: geometry)
    }

    func makeItem(kind: PresentationItemKind, title: String, restoredOrigin: PresentationOriginRestorer?,
                  onMove: @escaping (NSPoint, PresentationItemMoveReason) -> Void, onCancel: (() -> Void)?) -> any PresentationItem
    {
        let result = host.makeItem(kind: kind, title: title, restoredOrigin: restoredOrigin, onMove: onMove, onCancel: onCancel)
        item = result
        return result
    }
}
