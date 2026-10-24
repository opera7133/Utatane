import AppKit
import Foundation
import Testing
@testable import UtatanePlatformMacOS
import UtataneShell

@MainActor private func animationRestartFixture() throws -> (URL, SurfaceWindowController, ShellDefinition, UserDefaults) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)).write(to: root.appending(path: "surface0.png"))
    try makePNG(width: 2, height: 4, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)).write(to: root.appending(path: "surface1.png"))
    try makePNG(width: 2, height: 4, color: NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1)).write(to: root.appending(path: "surface2.png"))
    try """
    surface0 {
    animation7.interval,never
    animation7.pattern0,overlay,1,5000,0,0
    animation8.interval,never
    animation8.pattern0,overlay,2,0,2,0
    }
    """.write(to: root.appending(path: "surfaces.txt"), atomically: true, encoding: .utf8)
    try "seriko.use_self_alpha,1\nseriko.use_self_alpha_full,1\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    let (defaults, positions) = makePositionStore()
    let surfaces = SurfaceWindowController(positionStore: positions), shell = try ShellLoader().load(from: root)
    try surfaces.show(shell: shell, surfaceID: 0)
    return (root, surfaces, shell, defaults)
}

@Test @MainActor func `cancelled animation cleanup cannot erase a replacement after a surface redraw`() async throws {
    let (root, surfaces, shell, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    surfaces.playAnimation(identifier: "7")
    try await requireEventually { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
    var waiting = false
    let old = Task { @MainActor in
        waiting = true
        await surfaces.waitForAnimation(identifier: "7")
    }
    try await requireEventually { waiting }
    try surfaces.show(shell: shell, surfaceID: 0)
    surfaces.playAnimation(identifier: "7")
    await old.value
    #expect(surfaces.serikoInspectorSnapshots.first?.currentAnimationID == 7)
    #expect(surfaces.serikoInspectorSnapshots.first?.isAnimating == true)
}

@Test @MainActor func `retriggering an overlay retains its frame until the new animation publishes`() async throws {
    let (root, surfaces, _, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    surfaces.playAnimation(identifier: "7")
    try await requireEventually { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
    surfaces.playAnimation(identifier: "7")
    // A different synchronous layer forces a redraw before the replacement task runs.
    surfaces.playAnimation(identifier: "8")
    let image = try #require(surfaces.renderedImage()?.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: image))
    #expect(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)?.blueComponent ?? 0 > 0.9)
}

@Test @MainActor func `ending spectrum removes its timed overlays while retaining static display layers`() async throws {
    let (root, surfaces, _, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    surfaces.playAnimation(identifier: "7", owner: "OnSoundSpectrum")
    surfaces.playAnimation(identifier: "8", owner: "OnSoundSpectrum")
    try await requireEventually { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
    surfaces.stopTransientAnimations(owner: "OnSoundSpectrum")
    #expect(surfaces.serikoInspectorSnapshots.first?.isAnimating == false)
    #expect(surfaces.serikoInspectorSnapshots.first?.persistentAnimationIDs.contains(8) == true)
    #expect(surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == false)
    #expect(surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) > 0.9 } == true)
}

@Test @MainActor func `ending spectrum leaves unrelated animation running`() async throws {
    let (root, surfaces, _, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    surfaces.playAnimation(identifier: "7", owner: "OnOtherEvent")
    try await requireEventually { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
    surfaces.stopTransientAnimations(owner: "OnSoundSpectrum")
    #expect(surfaces.serikoInspectorSnapshots.first?.isAnimating == true)
    #expect(surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true)
}

@Test @MainActor func `static and timed animations share SERIKO layer order`() async throws {
    let (root, surfaces, _, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    let definition = root.appending(path: "surfaces.txt")
    let source = try String(contentsOf: definition, encoding: .utf8).replacingOccurrences(of: "overlay,2,0,2,0", with: "overlay,2,0,0,0")
    try source.write(to: definition, atomically: true, encoding: .utf8)
    try surfaces.show(shell: ShellLoader().load(from: root), surfaceID: 0)
    surfaces.playAnimation(identifier: "7")
    try await requireEventually { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
    surfaces.playAnimation(identifier: "8")
    let image = try #require(surfaces.renderedImage()?.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: image))
    #expect(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)?.greenComponent ?? 0 > 0.9)
}

@Test @MainActor func `runonce interpolate layers remain above lower numbered timed meters`() async throws {
    let (root, surfaces, _, defaults) = try animationRestartFixture()
    defer { surfaces.resetContent(); defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)); try? FileManager.default.removeItem(at: root) }
    try makePNG(width: 4, height: 4, color: .clear).write(to: root.appending(path: "surface0.png"))
    try """
    surface0 {
    animation7.interval,never
    animation7.pattern0,interpolate,1,5000,0,0
    animation8.interval,runonce
    animation8.pattern0,interpolate,2,0,0,0
    }
    """.write(to: root.appending(path: "surfaces.txt"), atomically: true, encoding: .utf8)
    try surfaces.show(shell: ShellLoader().load(from: root), surfaceID: 0)
    #expect(surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) > 0.9 } == true)
    surfaces.playAnimation(identifier: "7")
    try await requireEventually(timeout: .seconds(2)) { surfaces.renderedImage()?.containsColor { ($0.usingColorSpace(.deviceRGB)?.blueComponent ?? 0) > 0.9 } == true }
}
