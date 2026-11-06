import AppKit
import Testing
import UtataneCore
import UtataneModuleHost
@testable import UtatanePlatformMacOS
import UtataneSakuraScript
import UtataneShell
import UtataneShiori

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_SHELL"] != nil)) @MainActor
func `local CLDSP surface routes EQ switch coordinates`() throws {
    let root = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_CLDSP_SHELL"]))
    let shell = try ShellLoader().load(from: root)
    let controller = SurfaceWindowController()
    defer { controller.resetContent() }
    try controller.show(shell: shell, scope: 1, surfaceID: 9)
    let number = try #require(controller.windowNumbers.first)
    let window = try #require(NSApp.window(withWindowNumber: number))
    let view = try #require(window.contentView as? NSImageView)
    var received: String?
    controller.onMouseEvent = { event in received = event.region }
    print("CLDSP view", view.bounds, "image", view.image?.size as Any)
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 95, y: view.bounds.height - 176), modifierFlags: [], timestamp: 0, windowNumber: number, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    view.mouseDown(with: event)
    #expect(received == "mode_eq_on")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_SPECTRUM_SCRIPT"] != nil)) @MainActor
func `local CLDSP spectrum playback benchmark`() async throws {
    let root = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_CLDSP_SHELL"]))
    let scriptURL = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_CLDSP_SPECTRUM_SCRIPT"]))
    let script = try SakuraScript(rawValue: String(contentsOf: scriptURL, encoding: .utf8))
    let controller = SurfaceWindowController()
    defer { controller.resetContent() }
    let shell = try ShellLoader().load(from: root)
    try controller.show(shell: shell, scope: 1, surfaceID: 9)
    let player = SakuraScriptPlayer(surfaceWindowController: controller, balloonWindowController: BalloonWindowController())
    defer { player.cancel() }
    let balloon = makeBalloon(directory: root)
    await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
    let started = Date()
    for _ in 0 ..< 100 {
        await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
    }
    print("CLDSP spectrum render average seconds", Date().timeIntervalSince(started) / 100)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_GHOST"] != nil)) @MainActor
func `local CLDSP EQ controls redraw through SHIORI and SakuraScript`() async throws {
    let env = ProcessInfo.processInfo.environment
    let source = try URL(fileURLWithPath: #require(env["UTATANE_CLDSP_GHOST"]))
    let module = try URL(fileURLWithPath: #require(env["UTATANE_CLDSP_MODULE"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "cldsp-ui-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: source, to: root)
    let master = root.appending(path: "ghost/master")
    let handle = try FileHandle(forWritingTo: master.appending(path: "kawarirc.kis"))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\nOnUtataneEQSetup : $(set fullmode_sw 1;set spectrum_mode 1;set mode_eq 0;set eq_enabled 0;set playing 0;set startup_flg 1;entry spectrumdisp;)\nOnUtataneEQState : ${eq_enabled}|${mode_eq}|${eq_bank}\n".utf8))
    try handle.close()
    let session = try NativeShioriSession(directoryURL: master, moduleURL: module, moduleResolver: .init(allowsFallback: false))
    defer { try? session.close() }
    let adapter = GhostEventShioriAdapter()
    func response(_ event: GhostEvent) throws -> SakuraScript? {
        let wire = try session.request(adapter.request(for: event).serialized())
        return try ShioriMessageParser.parseResponse(wire).playableScriptValue.map(SakuraScript.init(rawValue:))
    }
    let shell = try ShellLoader().load(from: root.appending(path: "shell/master"))
    let controller = SurfaceWindowController()
    defer { controller.resetContent() }
    try controller.show(shell: shell, scope: 1, surfaceID: 9)
    let player = SakuraScriptPlayer(surfaceWindowController: controller, balloonWindowController: BalloonWindowController())
    defer { player.cancel() }
    player.onEmbeddedNotification = { id, args in
        _ = try? response(.notification(id: id, references: Dictionary(uniqueKeysWithValues: args.enumerated().map { ($0.offset, $0.element) })))
    }
    player.onTranslate = { script, context in
        try? response(.shiori(id: "OnTranslate", references: [0: script.rawValue, 2: context.eventID ?? ""]))
    }
    let balloon = makeBalloon(directory: root)
    let initial = try response(.shiori(id: "OnUtataneEQSetup", references: [:]))
    try await player.playAndWait(#require(initial), balloon: balloon)
    let beforeData = try #require(controller.renderedImage(for: 1)?.tiffRepresentation)
    let beforePixels = try #require(NSBitmapImageRep(data: beforeData))
    if let prefix = env["UTATANE_CLDSP_EQ_PREVIEW"] {
        let data = try #require(controller.renderedImage(for: 1)?.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: prefix + ".before.png"))
    }
    var reply: SakuraScript?
    controller.onMouseEvent = { event in
        guard !player.isTimeCritical else { return }
        reply = try? response(.mouse(event))
    }
    for x in [95, 139] {
        let number = try #require(controller.windowNumbers.first)
        let window = try #require(NSApp.window(withWindowNumber: number))
        let view = try #require(window.contentView)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: Int(view.bounds.height) - 176), modifierFlags: [], timestamp: 0, windowNumber: number, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        reply = nil
        view.mouseDown(with: event)
        try await player.playAndWait(#require(reply), balloon: balloon)
    }
    let result = try response(.shiori(id: "OnUtataneEQState", references: [:]))
    let state = try #require(result)
    #expect(state.rawValue == "1|1|2")
    let rendered = try #require(controller.renderedImage(for: 1)?.tiffRepresentation)
    let pixels = try #require(NSBitmapImageRep(data: rendered))
    // The EQ title replaces the spectrum title. Require new visible pixels,
    // so a blank frame cannot satisfy a simple before/after difference check.
    var changedVisiblePixels = 0
    for y in 185 ..< 194 {
        for x in 25 ..< 296 {
            if let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               let before = beforePixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               color.alphaComponent > 0.8,
               max(color.redComponent, color.greenComponent, color.blueComponent) > 0.3,
               abs(color.redComponent - before.redComponent) + abs(color.greenComponent - before.greenComponent)
               + abs(color.blueComponent - before.blueComponent) > 0.05
            {
                changedVisiblePixels += 1
            }
        }
    }
    #expect(changedVisiblePixels > 20)
    if let prefix = env["UTATANE_CLDSP_EQ_PREVIEW"] {
        let data = try #require(controller.renderedImage(for: 1)?.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: prefix + ".after.png"))
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_LIVE_BENCHMARK"] != nil)) @MainActor
func `local CLDSP live audio spectrum clock responsiveness`() async throws {
    let env = ProcessInfo.processInfo.environment
    let source = try URL(filePath: #require(env["UTATANE_CLDSP_GHOST"]))
    let module = try URL(filePath: #require(env["UTATANE_CLDSP_MODULE"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "cldsp-live-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: source.appending(path: "ghost/master"), to: root)
    let handle = try FileHandle(forWritingTo: root.appending(path: "kawarirc.kis"))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\nOnUtataneLiveSetup : $(set playing 1;set fullmode_sw 1;set spectrum_mode 1;set mode_eq 0;set surface.1 9;set cyclecounter 0;)\n".utf8))
    try handle.close()
    let native = try NativeShioriSession(directoryURL: root, moduleURL: module, moduleResolver: .init(allowsFallback: false))
    defer { try? native.close() }
    let adapter = GhostEventShioriAdapter()
    let setup = adapter.request(for: .shiori(id: "OnUtataneLiveSetup", references: [:])).serialized()
    _ = try native.request(setup)
    let surfaces = SurfaceWindowController()
    let shell = try ShellLoader().load(from: source.appending(path: "shell/master"))
    try surfaces.show(shell: shell, scope: 1, surfaceID: 9)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: BalloonWindowController())
    let sound = SakuraScriptSoundPlayer()
    sound.isMuted = true
    sound.resourceBaseDirectory = root
    defer { sound.discard(); player.cancel(); surfaces.resetContent() }
    let balloon = makeBalloon(directory: root)
    var frames = 0
    var positions: [Int] = []
    var heartbeatGaps: [Double] = []
    let heartbeat = Task { @MainActor in
        var last = Date()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
            let now = Date()
            heartbeatGaps.append(now.timeIntervalSince(last))
            last = now
        }
    }
    defer { heartbeat.cancel() }
    player.onTranslate = { script, context in
        let request = adapter.request(for: .shiori(id: "OnTranslate", references: [0: script.rawValue, 2: context.eventID ?? ""])).serialized()
        guard let wire = try? await native.requestAsync(request) else { return nil }
        return try? ShioriMessageParser.parseResponse(wire).playableScriptValue.map(SakuraScript.init(rawValue:))
    }
    sound.onSpectrum = { references in
        let request = adapter.request(for: .shiori(id: "OnSoundSpectrum", references: references)).serialized()
        if let wire = try? await native.requestAsync(request),
           let response = try? ShioriMessageParser.parseResponse(wire),
           let value = response.playableScriptValue
        {
            player.enqueuePeriodic(SakuraScript(rawValue: value), balloon: balloon, eventID: "OnSoundSpectrum")
        }
        frames += 1
        positions.append(Int(references[6] ?? "") ?? 0)
    }
    try await sound.execute(.play(file: "cldsp2.mp3", loop: true, options: ["--spectrum=100", "--spectrum-bands=31"]))
    try await requireEventually(timeout: .seconds(15)) { frames >= 20 }
    #expect(positions.last ?? 0 > 1500)
    #expect(!heartbeatGaps.isEmpty)
    let sorted = heartbeatGaps.sorted()
    try print("CLDSP live frames", frames, "media position ms", positions.last ?? 0,
              "main heartbeat p95 ms", sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000,
              "max ms", #require(sorted.last) * 1000)
}
