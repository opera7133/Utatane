import AppKit
import Testing
import UtataneBalloon
import UtataneCore
@testable import UtatanePlatformMacOS
import UtatanePlugin
import UtataneSakuraScript
import UtataneShell

@Test @MainActor
func `plugin input responses return to their origin and keep later choices owned`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        var ordinaryInputs = 0
        var pluginInputs: [String] = []
        player.onInputBox = { _ in ordinaryInputs += 1; return nil }
        player.onPluginInputBox = { origin, command, scope in
            pluginInputs.append(origin.id + ":" + command.id)
            #expect(scope == 0)
            return .init(script: SakuraScript(rawValue: #"\q[save,OnSaved]"#), origin: origin)
        }
        await player.playAndWait(SakuraScript(rawValue: #"\![open,inputbox,OnInputDiary]"#), balloon: balloon,
                                 characterDelayMilliseconds: 0, context: .init(pluginOrigin: .init(id: "diary")))
        #expect(pluginInputs == ["diary:OnInputDiary"])
        #expect(ordinaryInputs == 0)
        let link = try #require(balloons.textAndLinks(for: 0)?.1.first)
        #expect(link.id == "OnSaved")
        #expect(link.pluginOrigin?.id == "diary")
        await player.playAndWait(SakuraScript(rawValue: #"\![open,inputbox,OnOrdinary]"#), balloon: balloon, characterDelayMilliseconds: 0)
        #expect(ordinaryInputs == 1)
    }
}

@Test @MainActor
func `a ghost reply to plugin input keeps ghost ownership`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        var calls: [String] = []
        player.onPluginInputBox = { _, command, _ in
            calls.append("plugin:" + command.id)
            return .init(script: SakuraScript(rawValue: #"\![open,inputbox,OnGhostInput]\q[ghost,OnGhostChoice]"#), flags: ["plugin-event"])
        }
        player.onInputBox = { command in calls.append("ghost:" + command.id); return nil }
        await player.playAndWait(SakuraScript(rawValue: #"\![open,inputbox,OnPluginInput]"#), balloon: balloon,
                                 characterDelayMilliseconds: 0, context: .init(pluginOrigin: .init(id: "plugin")))
        #expect(calls == ["plugin:OnPluginInput", "ghost:OnGhostInput"])
        let link = try #require(balloons.textAndLinks(for: 0)?.1.first)
        #expect(link.pluginOrigin == nil)
    }
}

@MainActor
private func withPluginPlayer(_ body: @MainActor (SakuraScriptPlayer, BalloonWindowController, BalloonDefinition, URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "Plugin playback \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try makePNG(width: 30, height: 60).write(to: root.appending(path: "surface0000.png"))
    let image = try makePNG(width: 400, height: 360, color: NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1))
    for name in ["balloons0.png", "balloons2.png", "balloonk0.png"] {
        try image.write(to: root.appending(path: name))
    }
    try "type,balloon\nname,test\nuse_self_alpha,1\nvalidrect.left,20\nvalidrect.top,20\nvalidrect.right,380\nvalidrect.bottom,340\n".write(to: root.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
    let (defaults, positions) = makePositionStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
    let surfaces = SurfaceWindowController(positionStore: positions)
    try surfaces.show(shell: ShellDefinition(directory: root, surfaces: [:]), defaultSurfaceIDs: [0: 0])
    defer { surfaces.hideAll() }
    let balloons = BalloonWindowController(positionStore: positions)
    let player = SakuraScriptPlayer(surfaceWindowController: surfaces, balloonWindowController: balloons)
    player.configure(resourceBaseDirectory: root)
    defer { player.cancel() }
    try await body(player, balloons, BalloonLoader().load(from: root), root)
}

@Test @MainActor
func `plugin property completion keeps its origin and skips ghost translation`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        var calls: [String] = []
        var values: [String] = []
        var translations = 0
        player.onTranslate = { _, _ in translations += 1; return nil }
        player.onGetProperties = { _, _ in Issue.record("plugin completion reached the ghost"); return nil }
        player.onPluginEvent = { id, event, arguments, reflects in
            calls.append("\(id):\(event)")
            values = arguments
            #expect(reflects)
            return .init(script: SakuraScript(rawValue: #"\q[choose,OnSelect,one]"#), origin: .init(id: id))
        }
        let context = SakuraScriptPlaybackContext(flags: ["notranslate"], pluginOrigin: .init(id: "first"))
        await player.playAndWait(SakuraScript(rawValue: #"\b[2]\![get,property,OnSize,currentghost.balloon.scope(0).validwidth,currentghost.balloon.scope(0).validheight]"#), balloon: balloon, characterDelayMilliseconds: 0, context: context)
        #expect(calls == ["first:OnSize"])
        #expect(values == ["360", "320"])
        #expect(translations == 0)
        let link = try #require(balloons.textAndLinks(for: 0)?.1.first)
        #expect(link.pluginOrigin?.id == "first")
        #expect(link.pluginSelectionEvents(label: "choose").map(\.id) == ["OnChoiceSelectEx", "OnSelect"])
    }
}

@Test @MainActor
func `plugin nobreak reply waits for the parent dialogue`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        var contents: [String] = []
        var translations = 0
        player.onTranslate = { _, _ in translations += 1; return nil }
        player.onPlaybackFinished = { contents.append(balloons.textAndLinks(for: 0)?.0 ?? "") }
        player.onPluginEvent = { id, _, _, _ in
            .init(script: SakuraScript(rawValue: "queued"), origin: .init(id: id), flags: ["nobreak", "notranslate"])
        }
        player.play(SakuraScript(rawValue: #"before\![raiseplugin,p,OnTest]after"#), balloon: balloon, characterDelayMilliseconds: 0)
        try await requireEventually { contents.count == 2 }
        #expect(contents == ["beforeafter", "queued"])
        #expect(translations == 1)
        let anchor = BalloonTextLink(range: NSRange(location: 0, length: 1), id: "OnAnchor", arguments: ["extra"], kind: .anchor)
        #expect(anchor.pluginSelectionEvents(label: "label").map(\.id) == ["OnAnchorSelectEx", "OnAnchorSelect"])
        #expect(anchor.pluginSelectionEvents(label: "label").last?.arguments == ["OnAnchor"])
    }
}

@Test @MainActor
func `plugin choice hook runs once while ordinary ghost links stay ordinary`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        var pluginCalls = 0
        var ghostCalls = 0
        player.onChoiceSelection = { _, _, _ in ghostCalls += 1 }
        player.onPluginSelection = { origin, link, _ in
            #expect(origin.id == "plugin")
            #expect(link.id == "OnSelect")
            pluginCalls += 1
            return nil
        }
        await player.playAndWait(SakuraScript(rawValue: #"\q[choose,OnSelect]\q[plain,ordinary]"#), balloon: balloon,
                                 characterDelayMilliseconds: 0, context: .init(pluginOrigin: .init(id: "plugin")))
        let link = try #require(balloons.textAndLinks(for: 0)?.1.first)
        balloons.onLinkActivate?(link, "choose")
        balloons.onLinkClick?(link.id, link.arguments)
        try await requireEventually { pluginCalls == 1 }
        #expect(ghostCalls == 0)
        // The one-use hook has been consumed; the same old link no longer calls the plugin.
        balloons.onLinkActivate?(link, "choose")
        balloons.onLinkClick?(link.id, link.arguments)
        #expect(ghostCalls == 1)
        await player.playAndWait(SakuraScript(rawValue: #"\q[plain,ordinary]"#), balloon: balloon, characterDelayMilliseconds: 0)
        let ordinary = try #require(balloons.textAndLinks(for: 0)?.1.first)
        #expect(ordinary.pluginOrigin == nil)
        balloons.onLinkActivate?(ordinary, "plain")
        balloons.onLinkClick?(ordinary.id, ordinary.arguments)
        #expect(ghostCalls == 2)
        #expect(pluginCalls == 1)
    }
}

@Test @MainActor
func `absolute inline images are limited to configured content roots`() async throws {
    try await withPluginPlayer { player, balloons, balloon, _ in
        let allowed = FileManager.default.temporaryDirectory.appending(path: "allowed-balloons-\(UUID())")
        defer { try? FileManager.default.removeItem(at: allowed) }
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let image = allowed.appending(path: "preview.png")
        try makePNG(width: 20, height: 20).write(to: image)
        // Neither arbitrary absolute files nor symlinks can extend the allowed roots.
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: outside) }
        try makePNG(width: 20, height: 20).write(to: outside)
        try FileManager.default.createSymbolicLink(at: allowed.appending(path: "escape.png"), withDestinationURL: outside)
        player.additionalImageDirectories = [allowed]
        let script = "\\_b[\(image.path),inline]\\_b[\(outside.path),inline]\\_b[\(allowed.path)/escape.png,inline]"
        await player.playAndWait(SakuraScript(rawValue: script), balloon: balloon, characterDelayMilliseconds: 0)
        #expect(balloons.contentSnapshots(scopes: [0])[0]?.inlineImages.count == 1)
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_BALLOONSELECTOR_PLUGIN"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_YAYA_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
@MainActor
struct BalloonSelectorIntegrationTests {
    @Test func `real port displays every balloon across pages and dispatches selection and cancel`() async throws {
        try await withPluginPlayer { player, balloons, balloon, root in
            let plugins = root.appending(path: "plugins")
            let pluginDirectory = plugins.appending(path: "BalloonSelector")
            try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_BALLOONSELECTOR_PLUGIN"])), to: pluginDirectory)
            let plugin = try #require(PluginCatalog().load(from: [plugins]).first)
            let module = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_YAYA_MODULE"]))
            let transport = try DynamicLibraryPluginTransport(plugin: plugin, stateDirectoryURL: root.appending(path: "state"), moduleURLOverride: module)
            let content = root.appending(path: "balloons, [preview]")
            let names = (0 ..< 10).map { $0 == 0 ? "Card0, \"A\"[x]" : "Card\($0)" }
            for index in 0 ..< 10 {
                let path = content.appending(path: "card\(index)")
                try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                try "type,balloon\ncharset,UTF-8\nname,\(names[index])\n".write(to: path.appending(path: "descript.txt"), atomically: true, encoding: .utf8)
                try makeTopLeftKeyedPNG(width: 100, height: 60).write(to: path.appending(path: "balloons0.png"))
            }
            player.additionalImageDirectories = [content]
            var events: [String] = []
            var requests: [String] = []
            var actions: [SakuraScriptContentAction] = []
            player.onContentAction = { actions.append($0) }
            @MainActor func request(_ id: String, _ arguments: [String] = [], method: String = "GET") async throws -> SakuraScriptPluginPlayback? {
                requests.append(id)
                let response = try await transport.request(PluginRequest(method: method, id: id, charset: "UTF-8", sender: "Probe", references: Dictionary(uniqueKeysWithValues: arguments.enumerated().map { ($0.offset, $0.element) })))
                if let event = response.event {
                    events.append(event)
                }
                guard let script = response.script, !script.isEmpty else { return nil }
                let flags = (response.headers["ScriptOption"] ?? "").split(separator: ",").map(String.init)
                return .init(script: SakuraScript(rawValue: script), origin: .init(id: plugin.id), flags: flags)
            }
            _ = try await request("version")
            _ = try await request("balloonpathlist", [content.path + "/"], method: "NOTIFY")
            player.onPluginEvent = { _, id, arguments, _ in try? await request(id, arguments) }
            player.onPluginSelection = { _, link, label in
                for event in link.pluginSelectionEvents(label: label) {
                    if let reply = try? await request(event.id, event.arguments) {
                        return reply
                    }
                }
                return nil
            }
            let first = try #require(try await request("OnMenuExec"))
            await player.playAndWait(first.script, balloon: balloon, characterDelayMilliseconds: 0, context: first.context)
            let firstLinks = try #require(balloons.textAndLinks(for: 0)?.1)
            let firstCards = firstLinks.filter { $0.id == "OnPLUGINUTIL.BalloonChange" }
            #expect(firstCards.count == 9)
            #expect(balloons.contentSnapshots(scopes: [0])[0]?.inlineImages.count == 9)
            #expect(events.contains("OnBalloonSelectMenu"))
            if let path = ProcessInfo.processInfo.environment["UTATANE_BALLOONSELECTOR_PREVIEW"] {
                _ = try balloons.dumpBalloonImage(to: URL(filePath: path), scope: 0, prefix: "balloonselector-")
            }
            let next = try #require(firstLinks.first { $0.id == "OnBalloonSelectMenuOpen" && $0.arguments == ["1"] })
            balloons.onLinkActivate?(next, "next")
            balloons.onLinkClick?(next.id, next.arguments)
            try await requireEventually { balloons.textAndLinks(for: 0)?.1.filter { $0.id == "OnPLUGINUTIL.BalloonChange" }.count == 1 }
            let lastCards = try #require(balloons.textAndLinks(for: 0)?.1.filter { $0.id == "OnPLUGINUTIL.BalloonChange" })
            #expect(Set((firstCards + lastCards).flatMap(\.arguments)) == Set(names))
            let selected = try #require(lastCards.first)
            balloons.onLinkActivate?(selected, "selected")
            balloons.onLinkClick?(selected.id, selected.arguments)
            try await requireEventually { actions.contains(.changeBalloon(selected.arguments[0])) }
            #expect(events.contains("OnBalloonSelectExec"))
            let quotedSelection = try #require(try await request("OnPLUGINUTIL.BalloonChange", [names[0]]))
            await player.playAndWait(quotedSelection.script, balloon: balloon, characterDelayMilliseconds: 0, context: quotedSelection.context)
            #expect(actions.contains(.changeBalloon(names[0])))
            let again = try #require(try await request("OnMenuExec"))
            await player.playAndWait(again.script, balloon: balloon, characterDelayMilliseconds: 0, context: again.context)
            let cancel = try #require(balloons.textAndLinks(for: 0)?.1.first { $0.id == "PLUGINUTIL.Menu_CANCEL" })
            balloons.onLinkActivate?(cancel, "cancel")
            balloons.onLinkClick?(cancel.id, cancel.arguments)
            try await requireEventually { events.contains("OnBalloonSelectCancel") }
            #expect(requests.contains("OnPLUGINUTIL.GetBalloonSize"))
            await transport.shutdown()
        }
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_DBDIARY_PLUGIN"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_YAYA_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
@MainActor
struct DBdiaryIntegrationTests {
    @Test func `real diary input saves Japanese text and reads it after reload`() async throws {
        try await withPluginPlayer { player, _, balloon, root in
            let plugins = root.appending(path: "plugins")
            let directory = plugins.appending(path: "日記 Plugin")
            try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
            let source = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_DBDIARY_PLUGIN"]))
            try FileManager.default.copyItem(at: source, to: directory)
            // Some public NARs include a checkout. It is not needed to execute the dictionary.
            try? FileManager.default.removeItem(at: directory.appending(path: ".git"))
            let plugin = try #require(PluginCatalog().load(from: [plugins]).first)
            let module = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_YAYA_MODULE"]))
            let state = root.appending(path: "state")
            var transport = try DynamicLibraryPluginTransport(plugin: plugin, stateDirectoryURL: state, moduleURLOverride: module)
            @MainActor func request(_ id: String, _ references: [Int: String] = [:]) async throws -> PluginResponse {
                try await transport.request(PluginRequest(method: "GET", id: id, charset: "UTF-8", sender: "Probe", references: references))
            }
            #expect(try await request("version").statusCode == 200)
            let text = "日本語の日記 café 🌙"
            var inputIDs: [String] = []
            var ghostInputs = 0
            player.onInputBox = { _ in ghostInputs += 1; return nil }
            player.onPluginInputBox = { origin, command, _ in
                #expect(origin.id == plugin.id)
                inputIDs.append(command.id)
                guard case let .shiori(id, references) = SHIORIEventFactory.userInput(id: command.id, value: text) else { return nil }
                let response = try? await request(id, references)
                return response?.script.map { .init(script: SakuraScript(rawValue: $0), origin: origin) }
            }
            let open = try #require(try await request("OnCallInputBeautifulDiary").script)
            await player.playAndWait(SakuraScript(rawValue: open), balloon: balloon, characterDelayMilliseconds: 0,
                                     context: .init(flags: ["plugin-script"], pluginOrigin: .init(id: plugin.id)))
            #expect(inputIDs == ["OnInputBeautifulDiary"])
            #expect(ghostInputs == 0)
            let files = try FileManager.default.contentsOfDirectory(at: directory.appending(path: "Diary"), includingPropertiesForKeys: nil)
            let saved = try #require(files.first { (try? String(contentsOf: $0, encoding: .utf8).contains(text)) == true })
            let date = saved.deletingPathExtension().lastPathComponent
            let read = try await request("OnGetBeautifulDiary", [0: date, 1: "before:", 2: ":after", 3: "empty", 4: "missing"])
            #expect(read.script?.contains("before:" + text) == true)
            #expect(read.script?.contains(":after") == true)
            let beforeReload = try Data(contentsOf: saved)
            let cancel = SHIORIEventFactory.userInputCancel(id: "OnInputBeautifulDiary", timedOut: false)
            if case let .shiori(id, references) = cancel {
                _ = try await request(id, references)
            }
            #expect(try Data(contentsOf: saved) == beforeReload)
            await transport.shutdown()
            transport = try DynamicLibraryPluginTransport(plugin: plugin, stateDirectoryURL: state, moduleURLOverride: module)
            #expect(try await request("version").statusCode == 200)
            let reloaded = try await request("OnGetBeautifulDiary", [0: date, 1: "loaded:"])
            #expect(reloaded.script?.contains("loaded:" + text) == true)
            #expect(try Data(contentsOf: saved) == beforeReload)
            await transport.shutdown()
        }
    }
}

@Test @MainActor
func `plugin images stay relative to their origin and cannot escape through a symlink`() async throws {
    try await withPluginPlayer { player, balloons, balloon, root in
        let plugin = FileManager.default.temporaryDirectory.appending(path: "plugin-images-\(UUID())")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plugin) }
        try makePNG(width: 8, height: 8, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)).write(to: root.appending(path: "same.png"))
        try makePNG(width: 8, height: 8, color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)).write(to: plugin.appending(path: "same.png"))
        try FileManager.default.createSymbolicLink(at: plugin.appending(path: "escape.png"), withDestinationURL: root.appending(path: "same.png"))
        let script = SakuraScript(rawValue: #"\_b[same.png,inline,--option=use_self_alpha]\_b[escape.png,inline]"#)
        await player.playAndWait(script, balloon: balloon, characterDelayMilliseconds: 0,
                                 context: .init(pluginOrigin: .init(id: "images", resourceDirectory: plugin)))
        let images = try #require(balloons.contentSnapshots(scopes: [0])[0]?.inlineImages)
        #expect(images.count == 1)
        #expect(images.values.first?.colorAtCenter()?.blueComponent ?? 0 > 0.9)
        await player.playAndWait(SakuraScript(rawValue: #"\_b[same.png,inline,--option=use_self_alpha]"#), balloon: balloon, characterDelayMilliseconds: 0)
        let ordinary = try #require(balloons.contentSnapshots(scopes: [0])[0]?.inlineImages.values.first)
        #expect(ordinary.colorAtCenter()?.redComponent ?? 0 > 0.9)
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_AKARI_PLUGIN"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_AKARI_MODULE"] != nil
        && ProcessInfo.processInfo.environment["UTATANE_NATIVE_SHIORI_HOST"] != nil))
@MainActor
struct AkariPluginImageIntegrationTests {
    @Test func `real AKARI plugin toolbar renders its own images and dispatches cancel`() async throws {
        try await withPluginPlayer { player, balloons, balloon, root in
            let plugins = root.appending(path: "plugins")
            let directory = plugins.appending(path: "AKARI")
            try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
            let source = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_AKARI_PLUGIN"]))
            try FileManager.default.copyItem(at: source, to: directory)
            let plugin = try #require(PluginCatalog().load(from: [plugins]).first)
            let module = try URL(filePath: #require(ProcessInfo.processInfo.environment["UTATANE_AKARI_MODULE"]))
            let transport = try DynamicLibraryPluginTransport(plugin: plugin, stateDirectoryURL: root.appending(path: "state"), moduleURLOverride: module)
            let response = try await transport.request(PluginRequest(method: "GET", id: "showBottunSet", charset: "UTF-8"))
            let script = try #require(response.script)
            #expect(script.contains("fam_house.png"))
            let origin = SakuraScriptPluginOrigin(id: plugin.id, resourceDirectory: plugin.directory)
            await player.playAndWait(SakuraScript(rawValue: script), balloon: balloon, characterDelayMilliseconds: 0,
                                     context: .init(flags: ["notranslate"], pluginOrigin: origin))
            #expect(balloons.contentSnapshots(scopes: [0])[0]?.inlineImages.count == 4)
            let links = try #require(balloons.textAndLinks(for: 0)?.1)
            #expect(links.map(\.id).contains("Menu_CANCEL"))
            #expect(links.allSatisfy { $0.pluginOrigin?.resourceDirectory == plugin.directory })
            let cancel = try await transport.request(PluginRequest(method: "GET", id: "Menu_CANCEL", charset: "UTF-8"))
            #expect(cancel.script == #"\e"#)
            await transport.shutdown()
        }
    }
}
