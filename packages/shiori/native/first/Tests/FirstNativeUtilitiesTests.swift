import Foundation
import Testing
import UtataneCore
@testable import UtataneFirstNative
import UtataneSakuraScript

private func utilityMaster() -> URL? {
    ProcessInfo.processInfo.environment["UTATANE_FIRST_DLL"].map { URL(filePath: $0).deletingLastPathComponent() }
}

@Test func `FIRST utility dialogue is read from the supplied DLL while host guidance stays marked`() async throws {
    guard let master = utilityMaster() else { return }
    let strings = try FirstDLLAnalyzer(contentsOf: master.appending(path: "first.dll")).knownStringsByVirtualAddress()
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = try FirstNativeSession(masterDirectoryURL: master)
    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { Date(timeIntervalSince1970: 1000) }, stateRootURL: root)
    for (event, address): (String, UInt32) in [
        ("todo", 0x0047_F8E4), ("notify", 0x0047_F828),
        ("OnFIRSTTodoAdd", 0x0046_3F6C), ("OnFIRSTNotifyAdd", 0x0046_5154)
    ] {
        let script = try #require(await engine.handle(event: .choice(id: event, arguments: [])))
        let original = try #require(strings[address])
        #expect(script.rawValue.hasPrefix(NativeFirstPersonalityEngine.normalizeFIRSTScript(original)))
        #expect(script.rawValue.contains("\\_q[Utatane]"))
    }
    let added = try #require(await engine.handle(event: .shiori(id: "OnFIRSTNotifyInput", references: [0: "1m|SyntheticNote"])))
    #expect(try added.rawValue.hasPrefix(#require(strings[0x0046_56C0])))
    let weatherStart = try session.weatherStartScript()
    let originalStart = try #require(strings[0x0048_01EC])
    #expect(weatherStart.hasPrefix(originalStart.components(separatedBy: "\\![execute,")[0]))
    #expect(SakuraScriptParser().parse(weatherStart).contains(.weatherGet(eventID: "OnFIRSTWeather")))
    let weather = try session.currentWeatherScript(references: [0: "ok", 1: "61", 2: "12.3"])
    #expect(try weather.hasPrefix(#require(strings[0x0047_AE50])))
    let failed = try session.currentWeatherScript(references: [0: "denied"])
    #expect(try failed.hasPrefix(#require(strings[0x0047_AE88])))
    let cleaned = try #require(await engine.handle(event: .shiori(id: "OnRecycleBinEmpty", references: [4: "1"])))
    let originalCleanup = try #require(strings[0x0047_F678])
    let completion = try #require(originalCleanup.components(separatedBy: "\\![raise,Execute,clearrecyclebin]").last)
    #expect(cleaned.rawValue == "\\0" + completion + "\\e")
}

@Test func `FIRST reminder editing preserves file actions and cancellation does not change state`() async throws {
    guard let master = utilityMaster() else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1000)
    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { start }, stateRootURL: root)
    let store = FirstNativeStateStore(masterDirectoryURL: master, stateRootURL: root)
    _ = try await engine.handle(event: .shiori(id: "OnFIRSTNotifyInput", references: [0: "1m|Initial"]))
    let id = try #require(store.load()?.reminders?.first?.id)
    _ = try await engine.handle(event: .choice(id: "OnFIRSTNotifyFile", arguments: [id]))
    let path = "/tmp/通知 test.txt"
    _ = try await engine.handle(event: .shiori(id: "OnFIRSTNotifyFileInput", references: [0: path]))
    _ = try await engine.handle(event: .choice(id: "OnFIRSTNotifyEdit", arguments: [id]))
    _ = try await engine.handle(event: .shiori(id: "OnFIRSTNotifyInput", references: [0: "every2m|Edited"]))
    let saved = try #require(store.load()?.reminders?.first)
    #expect(saved.id == id && saved.filePath == path && saved.text == "Edited")
    _ = try await engine.handle(event: .choice(id: "OnFIRSTNotifyEdit", arguments: [id]))
    _ = try await engine.handle(event: .shiori(id: "OnUserInputCancel", references: [0: "OnFIRSTNotifyInput"]))
    #expect(store.load()?.reminders?.first == saved)
    let resumed = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { start.addingTimeInterval(121) }, stateRootURL: root)
    let script = try #require(await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "1"])))
    #expect(SakuraScriptParser().parse(script.rawValue).contains(.contentAction(.openFile(path))))
    #expect(store.load()?.reminders?.first?.filePath == path)
    _ = try await resumed.handle(event: .choice(id: "OnFIRSTNotifyFile", arguments: [id]))
    _ = try await resumed.handle(event: .shiori(id: "OnFIRSTNotifyFileInput", references: [0: ""]))
    #expect(store.load()?.reminders?.first?.filePath == nil)
}

@Test func `FIRST reminder file paths cannot introduce script commands`() {
    for path in ["relative.txt", "/tmp/x,evil", "/tmp/x]\\![execute,first-system,shutdown]", "/tmp/%username", "/tmp/\"x", "/tmp/x\n"] {
        #expect(FirstReminder.validatedFilePath(path) == nil)
        #expect(FirstReminder(text: "note", dueDate: .now, filePath: path).fileOpenScript.isEmpty)
    }
    #expect(FirstReminder.validatedFilePath("~/Documents/test.txt")?.hasPrefix("/") == true)
}

@Test func `FIRST repeating reminders skip missed intervals and retain their saved identity`() async throws {
    let start = Date(timeIntervalSince1970: 1000)
    let reminder = try #require(FirstReminder.parse("every10m|RepeatNote", now: start))
    #expect(reminder.followingDate(after: start.addingTimeInterval(3601)) == start.addingTimeInterval(4200))
    guard let master = utilityMaster() else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { start }, stateRootURL: root)
    _ = try await first.handle(event: .shiori(id: "OnFIRSTNotifyInput", references: [0: "every10m|RepeatNote"]))
    let store = FirstNativeStateStore(masterDirectoryURL: master, stateRootURL: root)
    let originalID = store.load()?.reminders?.first?.id
    let later = start.addingTimeInterval(3601)
    let resumed = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { later }, stateRootURL: root)
    let delivered = try #require(await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "1"])))
    #expect(delivered.rawValue.contains("RepeatNote"))
    #expect(store.load()?.reminders?.first?.id == originalID)
    #expect(store.load()?.reminders?.first?.dueDate == start.addingTimeInterval(4200))
    #expect(try await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "1"])) == nil)
}

@Test func `FIRST daily reminder uses local calendar time including daylight savings`() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let initial = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9)))
    let reminder = FirstReminder(text: "DailyNote", dueDate: initial, repeatRule: .daily(hour: 9, minute: 0))
    let next = try #require(reminder.followingDate(after: initial.addingTimeInterval(1), calendar: calendar))
    #expect(next.timeIntervalSince(initial) == 23 * 3600)
    #expect(calendar.component(.hour, from: next) == 9)
    #expect(FirstReminder.parse("daily09:00|message", now: initial)?.repeatRule == .daily(hour: 9, minute: 0))
    for invalid in ["daily24:00|message", "daily09:60|message", "every0m|message", "every525601m|message"] {
        #expect(FirstReminder.parse(invalid, now: initial) == nil)
    }
}

@Test func `FIRST weather and mail results display current data without executing header text`() throws {
    guard let master = utilityMaster() else { return }
    let session = try FirstNativeSession(masterDirectoryURL: master)
    let weatherCommand = try session.firstMenuChoiceScript(id: "weather", energy: 360)
    #expect(SakuraScriptParser().parse(weatherCommand ?? "").contains(.weatherGet(eventID: "OnFIRSTWeather")))
    let weather = try session.script(forEventID: "OnFIRSTWeather", references: [0: "ok", 1: "61", 2: "12.3", 3: "1"])
    #expect(weather?.contains("雨、12.3℃") == true)
    for status in ["denied", "unavailable", "timeout", "network"] {
        let result = try session.script(forEventID: "OnFIRSTWeather", references: [0: status])
        #expect(result?.contains("現在地は") == false)
    }
    let headers = #"From: \![execute,first-system,shutdown]"# + "\u{1}Subject: =?UTF-8?B?5pel5pys?="
    let mail = try session.script(forEventID: "OnBIFFComplete", references: [0: "3", 1: "2048", 2: "TestAccount", 4: headers])
    #expect(mail?.contains("日本") == true)
    #expect(mail?.contains("3通／2048バイト") == true)
    #expect(mail?.contains("ヘッダ取得: 1/3") == true)
    #expect(SakuraScriptParser().parse(mail ?? "").contains(.contentAction(.firstSystemAction("shutdown"))) == false)
    let fallback = try session.script(forEventID: "OnBIFFComplete", references: [0: "3"])
    #expect(fallback?.contains("件数のみ") == true)
    #expect(try session.script(forEventID: "OnBIFF2Complete", references: [0: "3", 1: "2048", 2: "TestAccount", 3: headers]) == mail)
}

@Test func `FIRST notes persist and can be edited completed and deleted`() async throws {
    guard let master = utilityMaster() else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master, stateRootURL: root)
    _ = try await engine.handle(event: .shiori(id: "OnFIRSTTodoInput", references: [0: #"note \s5 %username"#]))
    let store = FirstNativeStateStore(masterDirectoryURL: master, stateRootURL: root)
    let firstState = try #require(store.load())
    let item = try #require(firstState.todoItems?.first)
    #expect(item.text == #"note \s5 %username"#)
    let reloaded = try NativeFirstPersonalityEngine(masterDirectoryURL: master, stateRootURL: root)
    let menu = try #require(await reloaded.handle(event: .choice(id: "todo", arguments: [])))
    let tokens = SakuraScriptParser().parse(menu.rawValue)
    #expect(!tokens.contains(.surface(5)))
    #expect(!tokens.contains(.environmentVariable("username")))
    #expect(tokens.contains { token in
        guard case let .choice(_, id, arguments) = token else { return false }
        return id == "OnFIRSTTodoEdit" && arguments == [item.id]
    })
    _ = try await reloaded.handle(event: .choice(id: "OnFIRSTTodoEdit", arguments: [item.id]))
    _ = try await reloaded.handle(event: .shiori(id: "OnFIRSTTodoInput", references: [0: "edited note"]))
    _ = try await reloaded.handle(event: .choice(id: "OnFIRSTTodoToggle", arguments: [item.id]))
    #expect(store.load()?.todoItems?.first?.text == "edited note")
    #expect(store.load()?.todoItems?.first?.completed == true)
    _ = try await reloaded.handle(event: .choice(id: "OnFIRSTTodoDelete", arguments: [item.id]))
    #expect(store.load()?.todoItems?.isEmpty == true)
}

@Test func `FIRST reminders survive restart and deliver once when talking is allowed`() async throws {
    guard let master = utilityMaster() else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let start = Date(timeIntervalSince1970: 1000)
    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { start }, stateRootURL: root)
    _ = try await engine.handle(event: .shiori(id: "OnFIRSTNotifyInput", references: [0: "1m|TestReminder"]))
    let resumed = try NativeFirstPersonalityEngine(masterDirectoryURL: master, now: { start.addingTimeInterval(61) }, stateRootURL: root)
    #expect(try await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "0"])) == nil)
    let delivered = try #require(await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "1"])))
    #expect(delivered.rawValue.contains("TestReminder"))
    #expect(try await resumed.handle(event: .shiori(id: "OnSecondChange", references: [3: "1"])) == nil)
    let store = FirstNativeStateStore(masterDirectoryURL: master, stateRootURL: root)
    #expect(store.load()?.reminders?.isEmpty == true)
}

@Test func `FIRST utility storage errors leave notes unchanged`() async throws {
    guard let master = utilityMaster() else { return }
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root)
    let engine = try NativeFirstPersonalityEngine(masterDirectoryURL: master, stateRootURL: root)
    let response = try #require(await engine.handle(event: .shiori(id: "OnFIRSTTodoInput", references: [0: "UnsavedNote"])))
    #expect(response.rawValue.contains("保存失敗"))
    let menu = try #require(await engine.handle(event: .choice(id: "todo", arguments: [])))
    #expect(!menu.rawValue.contains("UnsavedNote"))
}

@Test func `FIRST reminder parser validates future dates and legacy state stays readable`() throws {
    let now = Date(timeIntervalSince1970: 1000)
    #expect(FirstReminder.parse("10m|message", now: now)?.dueDate == now.addingTimeInterval(600))
    for invalid in ["0m|message", "-1m|message", "1m|", "message", "2026-02-30 10:00|message", "525601m|message"] {
        #expect(FirstReminder.parse(invalid, now: now) == nil)
    }
    let future = FirstReminder.dateFormatter().string(from: now.addingTimeInterval(600))
    #expect(FirstReminder.parse("\(future)|message", now: now) != nil)
    let old = try JSONDecoder().decode(FirstNativePersistentState.self, from: Data(#"{"energy":360}"#.utf8))
    #expect(old.todoItems == nil && old.reminders == nil)
    #expect(FirstUtilityText.gravity("サクラ ABC") == "フハラ abc")
    #expect(FirstUtilityText.gravity("😀") == nil)
}

@Test func `FIRST converts kana and exposes only selected system commands`() throws {
    guard let master = utilityMaster() else { return }
    let session = try FirstNativeSession(masterDirectoryURL: master)
    #expect(try session.gurongiConvert("あいうえお") == "ガギグゲゴ")
    #expect(try session.gurongiConvert("アイウエオ") == "ガギグゲゴ")
    #expect(try session.gurongiConvert("あーABC") == "ガガABC")
    let shutdown = try session.script(forEventID: "On_exitwindows_yes")
    #expect(shutdown.map { SakuraScriptParser().parse($0).contains(.contentAction(.firstSystemAction("shutdown"))) } == true)
    let restart = try session.script(forEventID: "On_rebootwindows_yes")
    #expect(restart.map { SakuraScriptParser().parse($0).contains(.contentAction(.firstSystemAction("restart"))) } == true)
    #expect(try session.exitWindowsPromptScript().contains("On_exitwindows_yes"))
    #expect(try session.exitWindowsPromptScript().contains("Windows") == false)
    #expect(SakuraScriptParser().parse(session.choiceScript(id: "clearrecyclebin") ?? "").contains(.emptyRecycleBin))
    #expect(SakuraScriptParser().parse(#"\![execute,first-system,arbitrary]"#).contains(.contentAction(.firstSystemAction("arbitrary"))) == false)
    let memory = try session.refreshMemoryCompleteScript()
    #expect(SakuraScriptParser().parse(memory).first == .contentAction(.firstSystemAction("refreshmemory")))
    #expect(try session.script(forEventID: "OnFIRSTCompJapanTutorial")?.isEmpty == false)
}
