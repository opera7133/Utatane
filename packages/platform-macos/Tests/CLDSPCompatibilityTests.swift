import AppKit
import Testing
import UtataneCore
import UtataneModuleHost
@testable import UtatanePlatformMacOS
import UtataneRuntime
import UtataneSakuraScript
import UtataneShell
import UtataneShiori

@MainActor
private final class CLDSPClockTestState {
    var tick = 0
    var completions = 0
}

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_CLDSP_GHOST_PATH"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_KAWARI_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
func `native CLDSP aligns panels updates clock and renders imported and dropped tracks`() async throws {
    let environment = ProcessInfo.processInfo.environment
    let source = try URL(filePath: #require(environment["UTATANE_CLDSP_GHOST_PATH"]))
    let moduleURL = try URL(filePath: #require(environment["UTATANE_KAWARI_MODULE"]))
    if environment["UTATANE_TEST_SHARED_KAWARI"] == "1" {
        let resolved = try UtataneModuleResolver(environment: [:]).moduleURL(
            for: .kawari, masterDirectoryURL: source.appending(path: "ghost/master")
        )
        #expect(resolved?.standardizedFileURL == moduleURL.standardizedFileURL)
    }
    let root = FileManager.default.temporaryDirectory.appending(path: "CLDSP-test-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.copyItem(at: source, to: root)
    let master = root.appending(path: "ghost/master")
    for name in ["savedata_main.txt", "savedata_stocker.txt"] {
        try? FileManager.default.removeItem(at: master.appending(path: name))
    }
    let usesSpectrum = try String(contentsOf: master.appending(path: "kawari_main.txt"), encoding: .shiftJIS).contains("OnSoundSpectrum :")
    let config = try FileHandle(forWritingTo: master.appending(path: "kawarirc.kis"))
    try config.seekToEnd()
    try config.write(contentsOf: #require("""

    OnUtataneTestPlayLast : $(set mode_shuffle 0; set track $[ $(size playlist.p)-1 ]; entry サウンド手動再生;)
    OnUtataneTestPlaybackState : ${playing}|$confirm[2]|${tc.i}|${tc.p}
    OnUtataneTestMetadata : $(set @testid $[ $(size playlist.p)-1 ]; echo $playlist.t[${@testid}] "|" $playlist.l[${@testid}];)
    OnUtataneTestEnableSpectrum : $(set spectrum_mode 1; set fullmode_sw 1;)
    OnUtataneTestTiming : ${tc.i}|${tc.is}|${tc.p}|${rate}
    """.data(using: .shiftJIS)))
    try config.close()
    let session = try NativeShioriSession(
        directoryURL: master,
        moduleURL: moduleURL,
        saoriRootURL: environment["UTATANE_TEST_SAORI_ROOT"].map { URL(filePath: $0) }
    )
    @MainActor func request(_ id: String, _ references: [Int: String] = [:], method: String = "GET") async throws -> SakuraScript? {
        let headers = [ShioriHeader(name: "Charset", value: "UTF-8"), .init(name: "ID", value: id)]
            + references.sorted { $0.key < $1.key }.map { ShioriHeader(name: "Reference\($0.key)", value: $0.value) }
        let response = try await ShioriMessageParser.parseResponse(session.requestAsync(
            ShioriRequest(method: method, headers: .init(headers)).serialized()
        ))
        return response.value.flatMap { $0.isEmpty ? nil : SakuraScript(rawValue: $0) }
    }
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    surfaces.setPlacement(locksToDesktopBottom: false, keepsOnScreen: false)
    let shell = try ShellLoader().load(from: root.appending(path: "shell/master"))
    try surfaces.show(shell: shell, defaultSurfaceIDs: [0: 0, 1: 1, 2: 2, 3: 5, 4: 21, 5: 21])
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    player.isSoundMuted = true
    player.configure(resourceBaseDirectory: master)
    defer {
        player.configure(environmentVariables: [:])
        player.cancel(); player.discardSoundPlayback(); surfaces.hideAll()
        player.onGetProperties = nil
        player.onEmbeddedEvent = nil
        player.onEmbeddedNotification = nil
    }
    let balloon = makeBalloon(directory: root)
    var reloads = 0
    player.onContentAction = { action in
        guard action == .reloadShell else { return }
        do {
            try player.reloadShell(ShellLoader().load(from: root.appending(path: "shell/master")),
                                   defaultSurfaceIDs: [0: 0, 1: 1, 2: 2, 3: 5, 4: 21, 5: 21])
            reloads += 1
        } catch { Issue.record(error) }
    }
    var confirmations = 0
    player.onEmbeddedNotification = { id, arguments in
        if id.hasPrefix("OnScriptConfirm") {
            confirmations += 1
        }
        _ = try? await request(id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map { ($0.offset, $0.element) }), method: "NOTIFY")
    }
    player.onEmbeddedEvent = { id, arguments in
        try? await request(id, Dictionary(uniqueKeysWithValues: arguments.enumerated().map { ($0.offset, $0.element) }))
    }
    let startup = try #require(try await request("OnBoot"))
    await player.playAndWait(startup, balloon: balloon, characterDelayMilliseconds: 0)
    let main = try #require(surfaces.windowFrame(for: 0))
    for scope in [1, 2, 3] {
        #expect(surfaces.windowFrame(for: scope)?.minX == main.minX)
        #expect(surfaces.windowFrame(for: scope)?.maxY == main.maxY)
    }
    let clock = CLDSPClockTestState()
    player.onGetProperties = { event, properties in
        #expect(event == (usesSpectrum ? "OnMainDispRefresh" : "OnMainSyncMaster"))
        var values = ["2026", "10", "19", "1", "14", "23", String(clock.tick), "0", "0", "1024",
                      player.runtimePropertyValue(for: "currentghost.sound.index(0).position") ?? "-1"]
        if usesSpectrum {
            values.append(String(surfaces.serikoInspectorSnapshots.first { $0.scope == 1 }?.surfaceID ?? 1))
        }
        #expect(properties.count == values.count)
        clock.completions += 1
        return try? await request(event, Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.offset, $0.element) }))
    }
    var spectrumFrames = 0
    var spectrumTimings: [String] = []
    var nonzeroSpectrum = false
    player.onSoundSpectrum = { references in
        let started = ProcessInfo.processInfo.systemUptime
        spectrumFrames += 1
        nonzeroSpectrum = nonzeroSpectrum || (references[4]?.split(separator: "\u{1}").contains { (Int($0) ?? 0) > 0 } == true)
        if let script = try? await request("OnSoundSpectrum", references) {
            player.enqueuePeriodic(script, balloon: balloon, eventID: "OnSoundSpectrum")
        }
        spectrumTimings.append("\(references[6] ?? "?"):\(Int((ProcessInfo.processInfo.systemUptime - started) * 1000))")
    }
    defer {
        if let output = environment["UTATANE_TEST_PLAYBACK_METRICS"] {
            try? Data(spectrumTimings.joined(separator: ",").utf8).write(to: URL(filePath: output + ".spectrum"))
        }
    }
    if usesSpectrum {
        _ = try await request("OnUtataneTestEnableSpectrum")
    }
    var previousImage: Data?
    for second in 0 ..< 3 {
        clock.tick = second
        #expect(player.canTalk)
        let script = try #require(try await request("OnSecondChange", [0: "1", 1: "0", 2: "0", 3: "1", 4: "0"]))
        await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
        #expect(player.canTalk)
        let image = try #require(surfaces.renderedImage(for: 0)?.tiffRepresentation)
        if let previousImage {
            #expect(image != previousImage)
        }
        previousImage = image
    }
    #expect(clock.completions == 3)

    // Register real MP3 data through the original importer, then decode the
    // original playback command without playing music through the speakers.
    let realAudio = environment["UTATANE_TEST_AUDIO_PATH"].map { URL(filePath: $0) }
    let album = root.appending(path: "[2017] アルバム")
    try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
    let selected = realAudio ?? album.appending(path: "11. ダンスフロア.mp3")
    let dropped = realAudio ?? album.appending(path: "12. ドロップ.mp3")
    if realAudio == nil {
        for file in [selected, dropped] {
            try FileManager.default.copyItem(at: master.appending(path: "cldsp2.mp3"), to: file)
        }
    }
    let sound = SakuraScriptSoundPlayer()
    sound.isMuted = true
    sound.resourceBaseDirectory = master
    defer { sound.discard() }
    sound.onError = { _, error in Issue.record(error) }
    @MainActor func loadLastTrack(expected: URL) async throws {
        let playback = try #require(try await request("OnUtataneTestPlayLast"))
        let file = try #require(SakuraScriptParser().parse(playback.rawValue).compactMap { token -> String? in
            if case let .sound(.play(file, _, _)) = token {
                return file
            }
            return nil
        }.first)
        #expect(file.replacingOccurrences(of: "\\", with: "/") == expected.path)
        try await sound.execute(.load(file: file, options: []))
        #expect(sound.propertyValue(for: "currentghost.sound.index(0).name") == file)
        #expect(sound.outputVolume == 0)
        try await sound.execute(.stop)
        await player.playAndWait(playback, balloon: balloon, characterDelayMilliseconds: 0)
        let state = try #require(try await request("OnUtataneTestPlaybackState"))
        #expect(state.rawValue.hasPrefix("1|1|"))
    }
    @MainActor func finishImport() async throws {
        if usesSpectrum, let script = try await request("click.1tag_ready") {
            await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
        }
        for _ in 0 ..< 5 {
            if let script = try await request("OnSecondChange", [3: "1"]) {
                await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
            }
        }
    }
    let importScript = try #require(try await request("OnPlaylistImport", [0: "open", 1: "OnPlaylistImport", 2: selected.path]))
    await player.playAndWait(importScript, balloon: balloon, characterDelayMilliseconds: 0)
    try await finishImport()
    #expect(reloads >= 1)
    #expect(confirmations >= 1)
    if !usesSpectrum {
        #expect(surfaces.hasAnimation("1001", scope: 1))
    }
    let playlistImage = try #require(surfaces.renderedImage(for: 1)?.tiffRepresentation)
    let playlistBitmap = try #require(NSBitmapImageRep(data: playlistImage))
    // Generated title elements belong inside the playlist, not at the origin.
    #expect(playlistBitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
    if let output = environment["UTATANE_TEST_PLAYLIST_PREVIEW"] {
        let image = try #require(surfaces.renderedImage(for: 1)?.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: image))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: output))
        try Data(contentsOf: root.appending(path: "shell/master/surfaces_0gen.txt"))
            .write(to: URL(filePath: output + ".txt"))
    }
    if environment["UTATANE_TEST_SAORI_ROOT"] != nil {
        let metadata = try #require(try await request("OnUtataneTestMetadata"))
        let fields = metadata.rawValue.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(fields.count == 2)
        #expect(Int(fields.last ?? "0") ?? 0 > 1000)
        if realAudio != nil {
            #expect(fields.first == "ダンスフロアの果実")
        }
    }
    try await loadLastTrack(expected: selected)
    var dropEvents: [String] = []
    let dropResponses = try await FileDropEventRouter.responses(scope: 1, urls: [dropped]) { event in
        guard case let .shiori(id, references) = event else { return nil }
        dropEvents.append(id)
        return try await PersonalityResponse(script: request(id, references))
    }
    #expect(dropEvents == ["OnFileDrop2", "OnFileDropEx"])
    #expect(dropResponses.count == 1)
    for response in dropResponses {
        if let script = response.script {
            await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
        }
    }
    try await finishImport()
    #expect(reloads >= 2)
    if !usesSpectrum {
        #expect(surfaces.hasAnimation("1002", scope: 1))
    }
    try await loadLastTrack(expected: dropped)
    let soundID = player.runtimePropertyValue(for: "currentghost.sound.index(0).id")
    for _ in 0 ..< 3 {
        let script = try await request("OnSecondChange", [3: "1"]) ?? SakuraScript(rawValue: "\\e")
        #expect(!SakuraScriptParser().parse(script.rawValue).contains { token in
            if case .sound(.play) = token {
                return true
            }
            return false
        })
        await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
    }
    try await requireEventually {
        (Double(player.runtimePropertyValue(for: "currentghost.sound.index(0).position") ?? "") ?? 0) >= 1500
    }
    #expect(player.runtimePropertyValue(for: "currentghost.sound.index(0).id") == soundID)
    let state = try #require(try await request("OnUtataneTestPlaybackState"))
    let fields = state.rawValue.split(separator: "|")
    #expect(fields.count == 4)
    #expect(Int(fields.dropFirst(2).first ?? "0") ?? 0 > 0)
    #expect(Int(fields.last ?? "0") ?? 0 > 0)
    var redrawMilliseconds: [Int] = []
    for second in 2 ... 5 {
        try await requireEventually {
            (Int(player.runtimePropertyValue(for: "currentghost.sound.index(0).position") ?? "") ?? 0) >= second * 1000
        }
        clock.tick = second
        let started = ContinuousClock.now
        let script = try await request("OnSecondChange", [3: "1"]) ?? SakuraScript(rawValue: "\\e")
        await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0)
        let elapsed = started.duration(to: .now).components
        redrawMilliseconds.append(Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))
        let timing = try #require(try await request("OnUtataneTestTiming"))
        let counter = try #require(Int(timing.rawValue.split(separator: "|").first ?? ""))
        let position = try #require(Int(player.runtimePropertyValue(for: "currentghost.sound.index(0).position") ?? ""))
        #expect(abs(position - counter * (usesSpectrum ? 10 : 250)) < 750)
        let animations = try #require(surfaces.serikoInspectorSnapshots.first { $0.scope == 2 }).persistentAnimationIDs
        #expect(animations.contains(1150 + counter / (usesSpectrum ? 100 : 4) % 10))
        let numbers = surfaces.windowNumbers
        let ordered = NSApplication.shared.orderedWindows.map(\.windowNumber)
        for (front, back) in [(4, 0), (0, 3), (3, 1), (1, 2)] {
            #expect(try #require(ordered.firstIndex(of: numbers[front])) < #require(ordered.firstIndex(of: numbers[back])), "front=\(front) back=\(back) scopes=\(ordered.compactMap { numbers.firstIndex(of: $0) })")
        }
    }
    if let output = environment["UTATANE_TEST_PLAYBACK_METRICS"] {
        try Data(redrawMilliseconds.map(String.init).joined(separator: ",").utf8).write(to: URL(filePath: output))
    }
    #expect(redrawMilliseconds.allSatisfy { $0 < 1000 }, "Per-second updates must finish before the next tick: \(redrawMilliseconds)")
    if usesSpectrum {
        #expect(spectrumFrames >= 30)
        #expect(nonzeroSpectrum)
    }
    try await session.closeAsync()
}
