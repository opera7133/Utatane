import Foundation
import Testing
import UtataneCore
@testable import UtataneYuhnaNative

@Test
func `parses ordinary and random YDF events`() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-yuhna-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var data = Data("YDF/1.07 fixture".utf8)
    data.append(contentsOf: [0, 0, 0, 5])
    appendEvent("OnYuhnaRandomTalk", scripts: ["\\0A\\e", "\\0B\\e"], to: &data)
    appendEvent("OnBoot", scripts: ["\\0boot:%ref0\\e"], to: &data)
    appendConditionalEvent(
        label: "頭つつき@OnYuhnaMouseDoubleClick0",
        event: "OnYuhnaMouseDoubleClick0",
        condition: "%ref4 = Head",
        scripts: ["\\0head\\e"],
        to: &data
    )
    appendEvent("OnVariables", scripts: ["\\0{a=2}{b=3}{sum=(a+b)}{sum}\\e"], to: &data)
    appendConditionalEvent(
        label: "設定@OnYuhnaMouseDoubleClick0",
        event: "OnYuhnaMouseDoubleClick0",
        condition: "%sel = Interval-60",
        scripts: ["\\0interval\\e"],
        to: &data
    )
    try data.write(to: directory.appending(path: "dic.ydf"))

    let engine = try NativeYuhnaPersonalityEngine(masterDirectoryURL: directory)
    #expect(engine.loadedEventCount == 4)
    #expect(engine.loadedRuleCount == 5)
    #expect(engine.conditionalRuleCount == 2)
    let randomTalk = try await engine.handle(event: .randomTalk)?.rawValue ?? ""
    #expect(["\\0A\\e", "\\0B\\e"].contains(randomTalk))
    #expect(try await engine.handle(event: .shiori(id: "OnBoot", references: [0: "ref"]))?.rawValue == "\\0boot:ref\\e")
    #expect(try await engine.handle(event: .shiori(
        id: "OnYuhnaMouseDoubleClick0",
        references: [4: "Head"]
    ))?.rawValue == "\\0head\\e")
    #expect(try await engine.handle(event: .shiori(
        id: "OnChoiceSelect",
        references: [0: "Interval-60"]
    ))?.rawValue == "\\0interval\\e")
    #expect(try await engine.handle(event: .shiori(
        id: "OnVariables",
        references: [:]
    ))?.rawValue == "\\05\\e")
}

@Test(.enabled(if: hasInstalledYuhna))
func `loads installed Yuhna 10th dictionary`() async throws {
    let stateURL = FileManager.default.temporaryDirectory.appending(path: "utatane-yuhna-state-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: stateURL) }
    let engine = try NativeYuhnaPersonalityEngine(
        masterDirectoryURL: installedYuhnaMaster,
        stateStoreURL: stateURL
    )
    #expect(engine.loadedEventCount >= 40)
    #expect(engine.loadedRuleCount >= 60)
    #expect(engine.conditionalRuleCount >= 20)
    #expect(engine.skippedEventCount > 0)
    #expect(try await engine.handle(event: .boot)?.rawValue.contains("本日は御日柄も良く") == true)
    #expect(try await engine.handle(event: .randomTalk) != nil)
    let menu = try await engine.handle(event: .mouse(.init(
        kind: .doubleClick,
        scope: 0,
        region: nil,
        x: 0,
        y: 0
    )))
    #expect(menu?.rawValue.contains("OnYuhnaRandomTalk") == true)
    let head = try await engine.handle(event: .shiori(
        id: "OnYuhnaMouseDoubleClick0",
        references: [4: "Head"]
    ))
    #expect(head?.rawValue.contains("頭") == true)
    let headStroke = try await engine.handle(event: .shiori(
        id: "OnYuhnaMouseTouch0",
        references: [4: "Head"]
    ))
    #expect(headStroke?.rawValue == "\\0\\s[1]あー…こういうのは嬉しいかも？\\n")
    for x in 0 ..< 49 {
        #expect(try await engine.handle(event: .mouse(.init(
            kind: .move,
            scope: 0,
            region: "head",
            x: x * 2,
            y: 0
        )))?.rawValue.isEmpty == true)
    }
    let movedHeadStroke = try await engine.handle(event: .mouse(.init(
        kind: .move,
        scope: 0,
        region: "head",
        x: 100,
        y: 0
    )))
    #expect(movedHeadStroke?.rawValue == headStroke?.rawValue)
    let interval = try await engine.handle(event: .shiori(
        id: "OnChoiceSelect",
        references: [0: "Interval-60"]
    ))
    #expect(interval?.rawValue.contains("$i[60]") == false)
    for _ in 0 ..< 59 {
        #expect(try await engine.handle(event: .shiori(
            id: "OnSecondChange",
            references: [:]
        ))?.rawValue.isEmpty == true)
    }
    #expect(try await engine.handle(event: .shiori(id: "OnSecondChange", references: [:])) != nil)
    let namePrompt = try await engine.handle(event: .shiori(
        id: "OnChoiceSelect",
        references: [0: "SettingUserName"]
    ))
    #expect(namePrompt?.rawValue.contains(#"\![open,inputbox,OnYuhnaUsername,0]"#) == true)
    #expect(try await engine.handle(event: .shiori(
        id: "OnYuhnaUsername",
        references: [0: "Alice"]
    ))?.rawValue.contains("Aliceさん") == true)
    let restored = try NativeYuhnaPersonalityEngine(
        masterDirectoryURL: installedYuhnaMaster,
        stateStoreURL: stateURL
    )
    #expect(try await restored.handle(event: .shiori(
        id: "OnYuhnaUsername",
        references: [:]
    ))?.rawValue.contains("Aliceさん") == true)
}

@Test(.enabled(if: hasReferenceYuhna))
func `loads second observed YDF dictionary`() async throws {
    let stateURL = FileManager.default.temporaryDirectory.appending(path: "utatane-yuhna-reference-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: stateURL) }
    let engine = try NativeYuhnaPersonalityEngine(
        masterDirectoryURL: referenceYuhnaMaster,
        stateStoreURL: stateURL
    )
    #expect(engine.loadedEventCount >= 40)
    #expect(engine.conditionalRuleCount > 0)
    #expect(try await engine.handle(event: .boot) != nil)
    #expect(try await engine.handle(event: .randomTalk) != nil)
}

private func appendConditionalEvent(
    label: String,
    event: String,
    condition: String,
    scripts: [String],
    to data: inout Data
) {
    let labelBytes = Array(label.data(using: .shiftJIS) ?? Data())
    let eventBytes = Array(event.utf8)
    let conditionBytes = Array(condition.utf8)
    data.append(contentsOf: [UInt8(labelBytes.count >> 8), UInt8(labelBytes.count & 0xFF)])
    data.append(contentsOf: labelBytes)
    data.append(contentsOf: [UInt8(eventBytes.count >> 8), UInt8(eventBytes.count & 0xFF)])
    data.append(contentsOf: eventBytes)
    data.append(UInt8(conditionBytes.count))
    data.append(contentsOf: conditionBytes)
    data.append(0)
    data.append(UInt8(scripts.count))
    for script in scripts {
        let bytes = Array(script.utf8)
        data.append(contentsOf: [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF), 0])
        data.append(contentsOf: bytes)
    }
}

private func appendEvent(_ name: String, scripts: [String], to data: inout Data) {
    data.append(contentsOf: [UInt8(name.utf8.count >> 8), UInt8(name.utf8.count & 0xFF)])
    data.append(contentsOf: name.utf8)
    data.append(scripts.count > 1 ? 1 : 0)
    data.append(contentsOf: [0, 0, 0, UInt8(scripts.count)])
    for script in scripts {
        let bytes = Array(script.utf8)
        data.append(contentsOf: [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF), 0])
        data.append(contentsOf: bytes)
    }
}

private let repositoryRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
private let installedYuhnaMaster = repositoryRoot.appending(
    path: "Content/Local/Ghosts/yuhna/ghost/master",
    directoryHint: .isDirectory
)
private let hasInstalledYuhna = FileManager.default.fileExists(
    atPath: installedYuhnaMaster.appending(path: "dic.ydf").path
)
private let referenceYuhnaMaster = repositoryRoot.appending(
    path: "References/Local/girl-y_period2/ghost/master",
    directoryHint: .isDirectory
)
private let hasReferenceYuhna = FileManager.default.fileExists(
    atPath: referenceYuhnaMaster.appending(path: "dic.ydf").path
)
