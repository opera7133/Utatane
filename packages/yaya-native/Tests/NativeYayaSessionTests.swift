import Foundation
import Testing
import UtataneCore
import UtataneSakuraScript
import UtataneShiori
@testable import UtataneYayaNative

@Test func `native YAYA loads Emily and answers OnBoot`() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterURL = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/emily4/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        return
    }

    let session = try NativeYayaSession(masterDirectoryURL: masterURL)
    var headers = ShioriHeaders()
    headers.append(name: "Charset", value: "UTF-8")
    headers.append(name: "Sender", value: "Utatane")
    headers.append(name: "SecurityLevel", value: "local")
    headers.append(name: "ID", value: "OnBoot")
    for index in 0 ..< 8 {
        headers.append(name: "Reference\(index)", value: "")
    }

    let response = try session.request(ShioriRequest(method: "GET", headers: headers))
    #expect(response.statusCode == 200)
    #expect(response.value?.contains("\\h") == true)
    #expect(response.value?.hasSuffix("\\e") == true)
}

@Test func `native YAYA personality maps boot to SakuraScript`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterURL = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/emily4/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        return
    }

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    let script = try await engine.handle(event: .boot)

    #expect(script?.rawValue.contains("\\h") == true)
    #expect(script?.rawValue.hasSuffix("\\e") == true)

    let randomTalk = try await engine.handle(event: .randomTalk)
    #expect(randomTalk?.rawValue.isEmpty == false)
    #expect(randomTalk?.rawValue.hasSuffix("\\e") == true)
}

@Test func `installed ria restores her default surface after dialogue`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let installedMasterURL = repositoryRoot
        .appendingPathComponent("Content/Bundled/Ghosts/ria/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: installedMasterURL.path) else {
        return
    }
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(
        path: "utatane-ria-test-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let masterURL = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    try FileManager.default.copyItem(at: installedMasterURL, to: masterURL)

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    _ = try await engine.handle(event: .boot)
    let quickClose = try await engine.handle(event: .close)
    let script = try await engine.handle(event: .shiori(id: "OnSurfaceRestore", references: [:]))
    let state = try await engine.handle(event: .shiori(id: "OnRiaChoiceState", references: [:]))
    let activity = try await engine.handle(event: .shiori(id: "OnRiaChoiceActivity", references: [:]))
    let idleTalk = try await engine.handle(event: .shiori(
        id: "OnAITalkNewEvent",
        references: [4: "600"]
    ))
    for region in ["Head", "Face", "Bust", "Hand", "Leg", "Unknown"] {
        let doubleClick = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: region,
            x: 100,
            y: 50
        )))
        #expect(doubleClick?.rawValue.isEmpty == false, "missing double-click response for \(region)")
    }
    var secretTalk: SakuraScript?
    for region in ["Head", "Hand", "Head", "Face"] {
        secretTalk = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: region,
            x: 100,
            y: 50
        )))
    }
    _ = try await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "Bust",
        x: 100,
        y: 150
    )))
    let repeatedBustClick = try await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "Bust",
        x: 100,
        y: 150
    )))
    for _ in 0 ..< 3 {
        _ = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .doubleClick,
            scope: 0,
            region: "Bust",
            x: 100,
            y: 150
        )))
    }
    let annoyedState = try await engine.handle(event: .shiori(id: "OnRiaChoiceState", references: [:]))
    let apology = try await engine.handle(event: .shiori(id: "OnRiaChoiceApology", references: [:]))
    let annoyedHeadClick = try await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "Head",
        x: 100,
        y: 50
    )))
    _ = try await engine.handle(event: .shiori(id: "OnRiaChoiceApology", references: [:]))
    let repeatedApology = try await engine.handle(event: .shiori(id: "OnRiaChoiceApology", references: [:]))
    let profile = try await engine.handle(event: .shiori(id: "OnRiaChoiceProfile", references: [:]))
    let installBegin = try await engine.handle(event: .shiori(id: "OnInstallBegin", references: [:]))
    let installComplete = try await engine.handle(event: .shiori(
        id: "OnInstallCompleteEx",
        references: [0: "ghost", 1: "テストゴースト"]
    ))
    let installFailure = try await engine.handle(event: .shiori(
        id: "OnInstallFailure",
        references: [0: "extraction"]
    ))
    let ghostChanging = try await engine.handle(event: .ghostChanging(name: "テストゴースト"))
    let headlineBegin = try await engine.handle(event: .shiori(
        id: "OnHeadlinesenseBegin",
        references: [0: "テストニュース", 1: "https://example.test/"]
    ))
    let headlineItem = try await engine.handle(event: .shiori(
        id: "OnHeadlinesense.OnFind",
        references: [
            0: "テストニュース", 1: "https://example.test/article", 2: "First and Last", 3: "見出し"
        ]
    ))
    let rss = try await engine.handle(event: .shiori(
        id: "OnRSSComplete",
        references: [
            0: "テストフィード", 1: "https://example.test/", 2: "記事\u{1}https://example.test/article\u{1}\u{1}\u{1}概要"
        ]
    ))
    let scriptLab = try await engine.handle(event: .shiori(id: "OnRiaChoiceScriptLab", references: [:]))
    let shellChange = try await engine.handle(event: .shiori(
        id: "OnShellChanged",
        references: [0: "テストシェル"]
    ))
    let balloonChange = try await engine.handle(event: .shiori(
        id: "OnBalloonChange",
        references: [0: "テストバルーン"]
    ))
    let communicate = try await engine.handle(event: .shiori(
        id: "OnCommunicate",
        references: [0: "こんにちは"]
    ))
    let outfitMenu = try await engine.handle(event: .shiori(id: "OnRiaChoiceOutfit", references: [:]))
    let winter = try await engine.handle(event: .shiori(id: "OnRiaChoiceOutfitWinter", references: [:]))
    let winterRestore = try await engine.handle(event: .shiori(id: "OnSurfaceRestore", references: [:]))
    let outing = try await engine.handle(event: .shiori(id: "OnRiaChoiceGoWalk", references: [:]))
    let weatherMenu = try await engine.handle(event: .shiori(id: "OnRiaChoiceWeather", references: [:]))
    let weather = try await engine.handle(event: .shiori(
        id: "OnRiaWeatherResult",
        references: [0: "ok", 1: "61", 2: "18.5", 3: "1"]
    ))
    var receivedHeadPetResponse = false
    for x in 0 ..< 80 {
        let response = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .move,
            scope: 0,
            region: "Head",
            x: 80 + (x % 20),
            y: 50
        )))
        if response?.rawValue.isEmpty == false {
            receivedHeadPetResponse = true
        }
    }
    var receivedHairStrokeResponse = false
    for x in 0 ..< 80 {
        let response = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .move,
            scope: 0,
            region: "Hair",
            x: 80 + (x % 20),
            y: 50
        )))
        if response?.rawValue.isEmpty == false {
            receivedHairStrokeResponse = true
        }
    }
    #expect(["\\0\\s[0]\\e", "\\0\\s[10000]\\e", "\\0\\s[20000]\\e"].contains(script?.rawValue))
    #expect(["もう閉じる", "起動してすぐ閉じる"].contains {
        quickClose?.rawValue.contains($0) == true
    })
    #expect(state?.rawValue.isEmpty == false)
    #expect(activity?.rawValue.isEmpty == false)
    #expect(idleTalk?.rawValue.isEmpty == false)
    #expect(secretTalk?.rawValue.contains("隠し") == true)
    #expect(["\\s[9]", "\\s[10009]"].contains {
        repeatedBustClick?.rawValue.contains($0) == true
    })
    #expect(annoyedState?.rawValue.isEmpty == false)
    #expect(apology?.rawValue.isEmpty == false)
    #expect(["機嫌直して", "ごまかそう"].contains {
        annoyedHeadClick?.rawValue.contains($0) == true
    })
    #expect(repeatedApology?.rawValue.contains("言葉より次の行動") == true)
    #expect(profile?.rawValue.contains("起動回数") == true)
    #expect(installBegin?.rawValue.isEmpty == false)
    #expect(installComplete?.rawValue.contains("テストゴースト") == true)
    #expect(installFailure?.rawValue.contains("展開できなかった") == true)
    #expect(ghostChanging?.rawValue.contains("テストゴースト") == true)
    #expect(headlineBegin?.rawValue.contains("テストニュース") == true)
    #expect(headlineItem?.rawValue.contains("見出し") == true)
    #expect(headlineItem?.rawValue.contains("https://example.test/article") == true)
    #expect(rss?.rawValue.contains("記事") == true)
    #expect(rss?.rawValue.contains("https://example.test/article") == true)
    #expect(scriptLab?.rawValue.contains("\\_q") == true)
    #expect(scriptLab?.rawValue.contains("\\_a[OnRiaScriptLabAnchor]") == true)
    #expect(shellChange?.rawValue.contains("テストシェル") == true)
    #expect(balloonChange?.rawValue.isEmpty == false)
    #expect(communicate?.rawValue.contains("こんにちは") == true)
    #expect(outfitMenu?.rawValue.contains("外出着") == true)
    #expect(outfitMenu?.rawValue.contains("冬服") == true)
    #expect(winter?.rawValue.contains("\\s[20000]") == true)
    #expect(winterRestore?.rawValue == "\\0\\s[20000]\\e")
    #expect(outing?.rawValue.contains("\\s[-1]") == true)
    #expect(weatherMenu?.rawValue.contains("\\![execute,weather-get,--async=OnRiaWeatherResult]") == true)
    #expect(weather?.rawValue.contains("雨") == true)
    #expect(weather?.rawValue.contains("18.5度") == true)
    #expect(receivedHeadPetResponse)
    #expect(receivedHairStrokeResponse)
    let apologyAfterPet = try await engine.handle(event: .shiori(id: "OnRiaChoiceApology", references: [:]))
    #expect(apologyAfterPet?.rawValue.contains("言葉より次の行動") == false)
}

@Test func `installed ria offers a broad random talk pool`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let installedMasterURL = repositoryRoot
        .appendingPathComponent("Content/Bundled/Ghosts/ria/ghost/master", isDirectory: true)
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(
        path: "utatane-ria-talk-pool-test-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let masterURL = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    try FileManager.default.copyItem(at: installedMasterURL, to: masterURL)

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    _ = try await engine.handle(event: .boot)
    var talks = Set<String>()
    for _ in 0 ..< 600 {
        if let talk = try await engine.handle(event: .randomTalk), !talk.rawValue.isEmpty {
            talks.insert(talk.rawValue)
        }
    }

    #expect(talks.count >= 150)
    #expect(talks.contains { $0.contains("講義") || $0.contains("課題") })
    #expect(talks.contains { $0.contains("コード") || $0.contains("テスト") || $0.contains("エラー") })
    #expect(talks.contains { $0.contains("お兄") })
}

@Test func `installed ria resets pet count after idle or event`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let installedMasterURL = repositoryRoot
        .appendingPathComponent("Content/Bundled/Ghosts/ria/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: installedMasterURL.path) else {
        return
    }
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(
        path: "utatane-ria-pet-test-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let masterURL = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    try FileManager.default.copyItem(at: installedMasterURL, to: masterURL)

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    _ = try await engine.handle(event: .boot)

    // Pet head 7+ times to trigger too-much-pet state
    var tooMuchPetTriggered = false
    for _ in 0 ..< 10 {
        for x in 0 ..< 80 {
            if let response = try await engine.handle(event: .mouse(GhostMouseEvent(
                kind: .move,
                scope: 0,
                region: "Head",
                x: 80 + (x % 20),
                y: 50
            ))) {
                if ["撫ですぎ", "十分", "一回離して"].contains(where: { response.rawValue.contains($0) }) {
                    tooMuchPetTriggered = true
                }
            }
        }
    }
    #expect(tooMuchPetTriggered)

    let stateAfterManyPets = try await engine.handle(event: .shiori(id: "OnRiaChoiceState", references: [:]))
    #expect(stateAfterManyPets?.rawValue.contains("髪が気になる") == true)

    // Trigger AI talk event (simulates idle elapsed time)
    _ = try await engine.handle(event: .shiori(id: "OnAITalkNewEvent", references: [4: "600"]))

    // Petting again should no longer trigger the too-much-pet response
    var resetPetResponse = false
    for x in 0 ..< 80 {
        if let response = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .move,
            scope: 0,
            region: "Head",
            x: 80 + (x % 20),
            y: 50
        ))) {
            if !["撫ですぎ", "十分", "一回離して"].contains(where: { response.rawValue.contains($0) }) {
                resetPetResponse = true
            }
        }
    }
    #expect(resetPetResponse)
}

@Test func `native YAYA receives Emily double click and stroke events`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterURL = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/emily4/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        return
    }

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    let doubleClick = try await engine.handle(event: .mouse(GhostMouseEvent(
        kind: .doubleClick,
        scope: 0,
        region: "Head",
        x: 100,
        y: 50
    )))
    #expect(doubleClick?.rawValue.isEmpty == false)

    var receivedStrokeResponse = false
    for x in 0 ..< 80 {
        if let response = try await engine.handle(event: .mouse(GhostMouseEvent(
            kind: .move,
            scope: 0,
            region: "Head",
            x: 80 + (x % 40),
            y: 50
        ))) {
            receivedStrokeResponse = !response.rawValue.isEmpty
            break
        }
    }
    #expect(receivedStrokeResponse)
}

@Test func `native YAYA receives Emily installation events`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let masterURL = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/emily4/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        return
    }

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    let begin = try await engine.handle(event: .shiori(id: "OnInstallBegin", references: [:]))
    #expect(begin?.rawValue.isEmpty == false)

    let complete = try await engine.handle(event: .shiori(
        id: "OnInstallCompleteEx",
        references: [0: "ghost", 1: "Test Ghost", 2: "test-ghost"]
    ))
    #expect(complete?.rawValue.contains("インストール") == true)

    let failure = try await engine.handle(event: .shiori(
        id: "OnInstallFailure",
        references: [0: "unsupported"]
    ))
    #expect(failure?.rawValue.isEmpty == false)
}

@Test func `installed ria respects canTalk reference in OnSecondChange`() async throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let installedMasterURL = repositoryRoot
        .appendingPathComponent("Content/Bundled/Ghosts/ria/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: installedMasterURL.path) else {
        return
    }
    let temporaryRoot = FileManager.default.temporaryDirectory.appending(
        path: "utatane-ria-talkable-test-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    let masterURL = temporaryRoot.appending(path: "master", directoryHint: .isDirectory)
    try FileManager.default.copyItem(at: installedMasterURL, to: masterURL)

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
    _ = try await engine.handle(event: .boot)

    let silent = try await engine.handle(event: .shiori(
        id: "OnSecondChange",
        references: [0: "0", 1: "0", 2: "0", 3: "0"]
    ))
    #expect(silent == nil)
}
