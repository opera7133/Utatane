import AppKit
import Testing
@testable import UtataneCore
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell

@MainActor
struct SuspensionTests {
    @Test func `new speech waits for restore and cancelled translation cannot start playback`() async throws {
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let surfaces = SurfaceWindowController(positionStore: positions)
        let balloons = BalloonWindowController(positionStore: positions)
        let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
        defer { player.cancel(); surfaces.resetContent(); balloons.resetContent() }
        let balloon = makeBalloon(directory: FileManager.default.temporaryDirectory)
        var calls: [String] = []
        player.onEmbeddedEvent = { id, _ in calls.append(id); return nil }
        player.setSuspended(true)
        var completed = false
        let speech = Task {
            await player.playAndWait(SakuraScript(rawValue: #"\![raise,OnProbe]\e"#), balloon: balloon)
            completed = true
        }
        defer { speech.cancel() }
        try await requireEventually { player.isDialogueActive }
        #expect(calls.isEmpty)
        #expect(!completed)
        player.setSuspended(false)
        try await requireEventually { completed }
        #expect(calls == ["OnProbe"])

        var translation: CheckedContinuation<SakuraScript?, Never>?
        player.onTranslate = { _, _ in await withCheckedContinuation { translation = $0 } }
        player.play(SakuraScript(rawValue: #"\![raise,MustNotRun]\e"#), balloon: balloon)
        try await requireEventually { translation != nil }
        player.setSuspended(true)
        translation?.resume(returning: nil)
        player.setSuspended(false)
        player.onTranslate = nil
        await player.playAndWait(SakuraScript(rawValue: #"\![raise,AfterRestore]\e"#), balloon: balloon)
        #expect(calls == ["OnProbe", "AfterRestore"])
    }

    @Test func `suspension freezes delays without polling and cancellation releases waiters`() async throws {
        var now = ContinuousClock.now
        let clock = SuspensionClock(now: { now })
        now = now.advanced(by: .seconds(10))
        #expect(clock.elapsed == .seconds(10))
        var result: Bool?
        let timer = Task { result = await clock.sleep(for: .seconds(3600)) }
        try await requireEventually { clock.timerCount == 1 }
        clock.setSuspended(true)
        try await requireEventually { clock.waitingCount == 1 && clock.timerCount == 0 }
        now = now.advanced(by: .seconds(86400))
        #expect(clock.elapsed == .seconds(10))
        clock.setSuspended(false)
        try await requireEventually { clock.timerCount == 1 }
        #expect(result == nil)
        timer.cancel()
        try await requireEventually { result != nil }
        #expect(result == false)
        #expect(clock.timerCount == 0)

        clock.setSuspended(true)
        let waiting = Task { await clock.waitUntilActive() }
        try await requireEventually { clock.waitingCount == 1 }
        waiting.cancel()
        #expect(await waiting.value == false)
        #expect(clock.waitingCount == 0)
        let discarded = Task { await clock.waitUntilActive() }
        try await requireEventually { clock.waitingCount == 1 }
        clock.finish()
        #expect(await discarded.value == false)
        #expect(clock.waitingCount == 0)
    }

    @Test func `suspended surface releases cache and resumes the same animation`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1))
            .write(to: directory.appending(path: "surface0.png"))
        try makePNG(width: 4, height: 4, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
            .write(to: directory.appending(path: "surface1.png"))
        let shell = ShellDefinition(directory: directory, surfaces: [0: SurfaceDefinition(
            id: 0, collisions: [], animations: [SurfaceAnimation(id: 0, interval: nil, patterns: [
                SurfaceAnimationPattern(order: 0, method: "base", surfaceID: 1, waitMilliseconds: 1000, x: 0, y: 0)
            ])]
        )], usesSelfAlpha: true)
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let controller = SurfaceWindowController(positionStore: positions)
        defer { controller.resetContent() }
        try controller.show(shell: shell, scope: 0, surfaceID: 0)
        let base = try #require(controller.renderedImage())
        #expect(controller.cachedImageCount(scope: 0) > 0)
        controller.setSuspended(true)
        #expect(controller.cachedImageCount(scope: 0) == 0)
        var completed = false
        let animation = Task {
            await controller.playAnimationAndWait(id: 0)
            completed = true
        }
        defer { animation.cancel() }
        try await requireEventually { controller.serikoInspectorSnapshots.first?.isAnimating == true }
        #expect(controller.renderedImage() === base)
        #expect(!completed)
        controller.setSuspended(false)
        try await requireEventually { controller.renderedImage()?.colorAtCenter()?.blueComponent ?? 0 > 0.9 }
        let active = controller.renderedImage()
        controller.setSuspended(true)
        #expect(controller.renderedImage() === active)
        #expect(controller.cachedImageCount(scope: 0) == 0)
        controller.setSuspended(false)
        try await requireEventually { completed }
        #expect(controller.renderedImage()?.colorAtCenter()?.redComponent ?? 0 > 0.9)

        controller.setSuspended(true)
        let discarded = Task { await controller.playAnimationAndWait(id: 0) }
        try await requireEventually { controller.serikoInspectorSnapshots.first?.isAnimating == true }
        controller.resetContent()
        await discarded.value
        #expect(controller.cachedImageCount(scope: 0) == 0)
    }

    @Test func `suspension pauses animated images and stays independent from presentation hiding`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try #require(Data(base64Encoded: animatedPNGBase64))
        try png.write(to: directory.appending(path: "surface0.png"))
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let controller = SurfaceWindowController(positionStore: positions)
        defer { controller.resetContent() }
        try controller.show(shell: ShellDefinition(directory: directory, surfaces: [:], usesSelfAlpha: true), scope: 0, surfaceID: 0)
        #expect(controller.isImageAnimationEnabled())
        controller.setPresentationHidden(true)
        controller.setSuspended(true)
        #expect(!controller.isImageAnimationEnabled())
        controller.setSuspended(false)
        #expect(controller.isImageAnimationEnabled())
        controller.setSuspended(true)
        controller.setPresentationHidden(false)
        #expect(!controller.isImageAnimationEnabled())
    }
}
