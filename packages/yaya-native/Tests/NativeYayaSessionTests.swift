import Foundation
import Testing
import UtataneCore
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
    let masterURL = repositoryRoot
        .appendingPathComponent("Content/Local/Ghosts/ria/ghost/master", isDirectory: true)
    guard FileManager.default.fileExists(atPath: masterURL.path) else {
        return
    }

    let engine = try NativeYayaPersonalityEngine(masterDirectoryURL: masterURL)
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
        #expect(doubleClick?.rawValue.isEmpty == false)
    }
    var receivedHeadPetResponse = false
    for x in 0 ..< 40 {
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
    #expect(script?.rawValue == "\\0\\s[0]\\e")
    #expect(state?.rawValue.isEmpty == false)
    #expect(activity?.rawValue.isEmpty == false)
    #expect(idleTalk?.rawValue.isEmpty == false)
    #expect(receivedHeadPetResponse)
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
