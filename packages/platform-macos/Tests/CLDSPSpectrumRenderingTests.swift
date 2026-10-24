import AppKit
import Testing
@testable import UtatanePlatformMacOS
import UtataneShell

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_GHOST_PATH"] != nil))
@MainActor func `local CLDSP spectrum effects preserve meter holes and master level changes`() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["UTATANE_CLDSP_GHOST_PATH"])
    let (defaults, positions) = makePositionStore()
    let surfaces = SurfaceWindowController(positionStore: positions)
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let shell = try ShellLoader().load(from: URL(filePath: path).appending(path: "shell/master"))
    try surfaces.show(shell: shell, defaultSurfaceIDs: [1: 9])
    func bitmap() throws -> NSBitmapImageRep {
        let data = try #require(surfaces.renderedImage(for: 1)?.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: data))
    }
    let original = try bitmap()
    if let output = ProcessInfo.processInfo.environment["UTATANE_TEST_SPECTRUM_PREVIEW"] {
        try #require(original.representation(using: .png, properties: [:])).write(to: URL(filePath: output + ".base.png"))
    }
    let originalBlue = original.colorAt(x: 99, y: 295)?.usingColorSpace(.deviceRGB)?.blueComponent ?? 0
    #expect(originalBlue < 0.7)
    surfaces.setAnimationOffset(identifier: "50", x: -20, y: 0, scope: 1)
    surfaces.playAnimation(identifier: "50", scope: 1)
    try await requireEventually(timeout: .seconds(2)) {
        try bitmap().colorAt(x: 99, y: 295)?.usingColorSpace(.deviceRGB)?.blueComponent ?? 0 > 0.7
    }
    // The upper half is a transparent hole, the lower half contains the meter.
    surfaces.setAnimationOffset(identifier: "100", x: 0, y: 40, scope: 1)
    surfaces.playAnimation(identifier: "100", scope: 1)
    try await requireEventually(timeout: .seconds(2)) {
        try bitmap().colorAt(x: 48, y: 260)?.alphaComponent ?? 0 > 0.9
    }
    surfaces.playAnimation(identifier: "201", scope: 1)
    surfaces.playAnimation(identifier: "202", scope: 1)
    let colored = try bitmap()
    #expect(colored.colorAt(x: 48, y: 200)?.alphaComponent ?? 1 < 0.1)
    #expect(colored.colorAt(x: 48, y: 260)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0 > 0.4)
    #expect(colored.colorAt(x: 99, y: 295)?.alphaComponent ?? 0 > 0.9)
    let dumps = FileManager.default.temporaryDirectory.appending(path: "cldsp-meters-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dumps) }
    #expect(try surfaces.dumpSurfaceImages(to: dumps, scope: 1, surfaceList: "3400,3448") == 2)
    let low = try #require(NSBitmapImageRep(data: Data(contentsOf: dumps.appending(path: "surface3400.png"))))
    let high = try #require(NSBitmapImageRep(data: Data(contentsOf: dumps.appending(path: "surface3448.png"))))
    #expect(low.colorAt(x: 50, y: 0)?.alphaComponent ?? 1 < 0.1)
    #expect(high.colorAt(x: 50, y: 0)?.alphaComponent ?? 0 > 0.9)
    if let output = ProcessInfo.processInfo.environment["UTATANE_TEST_SPECTRUM_PREVIEW"] {
        try #require(colored.representation(using: .png, properties: [:])).write(to: URL(filePath: output))
    }
}
