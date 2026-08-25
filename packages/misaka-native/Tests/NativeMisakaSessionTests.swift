import Foundation
import Testing
import UtataneCore
@testable import UtataneMisakaNative
import UtataneNativeSaori
import UtataneShiori

@Test func `loads a MISAKA dictionary and answers boot`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {
    {$username="ユーザ"}
    }

    $OnBoot
    \\0起動。{$username}。\\e
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    let response = try session.request(request(id: "OnBoot"))
    #expect(response.value == #"\0起動。ユーザ。\e"#)
}

@Test func `supports conditions references and sequential candidates`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $OnChoiceSelect; {$if ({$reference(0)}=="talk")}
    {$_Talk}

    $_Talk; sequential;
    A

    B
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    let first = try session.request(request(id: "OnChoiceSelect", references: [0: "talk"]))
    let second = try session.request(request(id: "OnChoiceSelect", references: [0: "talk"]))
    #expect(first.value == "A")
    #expect(second.value == "B")
}

@Test func `evaluates integer arithmetic without executing Foundation expressions`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $OnBoot
    {$value=(1+2)*4}{$value}
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    #expect(try session.request(request(id: "OnBoot")).value == "12")
}

@Test func `supports array indexes dictionary copies and exponentiation`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Words
    zero

    one

    $_Variable
    {
    {$list=""}{$append($list,"A")}{$append($list,"B")}
    }

    $OnBoot
    {$copy($_Words,$words)}{$list[1]}:{$words[0]}:{$calc(2^3^2)}
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    #expect(try session.request(request(id: "OnBoot")).value == "B:zero:512")
}

@Test func `applies common conditions to every symbol in a dictionary file`() throws {
    let master = try makeMisakaMaster(dictionary: """
    #_Common
    {$if ({$mode}==1)}

    $OnBoot
    hidden
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    #expect(try session.request(request(id: "OnBoot")).statusCode == 204)
}

@Test func `nonoverlap visits every value before repeating`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $OnBoot; nonoverlap;
    A

    B

    C
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    let values = try (0 ..< 3).map { _ in try #require(session.request(request(id: "OnBoot")).value) }
    #expect(Set(values) == Set(["A", "B", "C"]))
}

@Test func `restores variables between defaults and constants and honors backup`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {$saved="default"}

    $_Constant
    {$constant="fresh"}

    $OnBoot
    {$backup()}{$saved}:{$constant}
    """)
    let state = master.deletingLastPathComponent().appending(path: "state.json")
    let saved = ["saved": ["restored"], "constant": ["stale"]]
    try JSONEncoder().encode(saved).write(to: state)
    let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
    #expect(try session.request(request(id: "OnBoot")).value == "restored:fresh")
    let persisted = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: state))
    #expect(persisted["constant"] == ["fresh"])
}

@Test func `updates elapsed system variables and schedules MISAKA random talk`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {$_talkinterval=1}

    $_OnRandomTalk
    TALK
    """)
    let clock = MisakaTestClock(Date(timeIntervalSince1970: 1000))
    let session = try NativeMisakaSession(
        masterDirectoryURL: master,
        saoriCaller: RecordingSaoriCaller(),
        now: { clock.now }
    )
    #expect(try session.request(request(id: "OnSecondChange")).statusCode == 204)
    clock.now = clock.now.addingTimeInterval(2)
    let response = try session.request(request(id: "OnSecondChange"))
    #expect(response.value == "TALK")
}

@Test func `calls the property change handler when enabled`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $__OnPropertyChanged
    {$observed={$name}}

    $OnBoot
    {$value=1}{$observed}
    """, options: "propertyhandler,1\n")
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    #expect(try session.request(request(id: "OnBoot")).value == "$value")
}

@Test func `writes native MISAKA diagnostics beside external state`() throws {
    let master = try makeMisakaMaster(dictionary: "$OnBoot\nOK", options: "error,1\n")
    let state = master.deletingLastPathComponent().appending(path: "state/misaka-vars.json")
    _ = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
    let log = state.deletingLastPathComponent().appending(path: "misaka_error.txt")
    #expect(try String(contentsOf: log, encoding: .utf8).contains("no load errors"))
}

@Test func `tracks other ghosts from baseware notifications`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $OnBoot
    {$isghostexists("花ちゃん")}
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    _ = try session.request(request(id: "otherghostname", references: [0: "花ちゃん\u{1}0\u{1}0"]))
    #expect(try session.request(request(id: "OnBoot")).value == "true")
    _ = try session.request(request(id: "OnOtherGhostClosed", references: [0: "花ちゃん"]))
    #expect(try session.request(request(id: "OnBoot")).value == "false")
}

@Test func `supports MISAKA byte strings kana and array operations`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {
    {$source=""}{$append($source,"あさ")}{$append($source,"いす")}
    }

    $OnBoot
    {$copy($source,$work)}{$stringexists($work,"あさ")}:{$count($work)}:{$popmatchl($work,"あ")}:{$count($work)}:{$substring("あいう",2,2)}:{$substringr("あいう",2)}:{$index("い","あいう")}:{$hiraganacase("カナ")}
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    let response = try session.request(request(id: "OnBoot"))
    #expect(response.value == "true:2:あさ:1:い:う:2:かな")
}

@Test func `returns appended SHIORI headers and communicate target`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $OnBoot
    {$to="花ちゃん"}{$appendheader("Extra: value")}送信
    """)
    let session = try NativeMisakaSession(masterDirectoryURL: master)
    let response = try session.request(request(id: "OnBoot"))
    #expect(response.headers["Reference0"] == "花ちゃん")
    #expect(response.headers["Extra"] == "value")
}

@Test func `persists user variables outside the master directory`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {
    {$count=0}
    }

    $OnBoot
    {$count++}回

    $OnClose
    \\-
    """)
    let state = master.deletingLastPathComponent().appending(path: "state.json")
    do {
        let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
        #expect(try session.request(request(id: "OnBoot")).value == "回")
        _ = try session.request(request(id: "OnClose"))
    }
    let saved = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: state))
    #expect(saved["count"] == ["1"])
}

@Test func `detects MISAKA by its ini file even when the DLL was renamed`() throws {
    let master = try makeMisakaMaster(dictionary: "$OnBoot\nOK")
    #expect(NativeMisakaPersonalityEngine.supports(masterDirectoryURL: master))
}

@Test func `answers boot from the installed misaka101 sample without Wine`() throws {
    let master = repositoryRoot
        .appending(path: "Content/Local/Ghosts/misaka101/ghost/master")
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    let state = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
    let response = try session.request(request(id: "OnBoot"))
    #expect(response.value == #"\0\s0\1\s0\0\s0起動。\e"#)
    #expect(try session.request(request(id: "OnAITalk")).value?.contains("ランダムトークテンプレート") == true)

    let receive = try session.request(request(
        id: "OnCommunicate",
        references: [0: "花ちゃん", 1: "こんにちは"]
    ))
    #expect(receive.value?.contains("こんにちは") == true)

    let send = try session.request(request(id: "OnChoiceSelect", references: [0: "ghostcommunicate"]))
    #expect(send.value?.contains("知ってる人は誰もいない") == true)
}

@Test func `answers boot from renamed MISAKA in the Juda sample without Wine`() throws {
    let master = repositoryRoot
        .appending(path: "Content/Local/Ghosts/Juda-System/ghost/master")
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    let state = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let session = try NativeMisakaSession(masterDirectoryURL: master, variableStoreURL: state)
    let response = try session.request(request(id: "OnBoot"))
    #expect(response.value?.contains("ユーザ") == true)
    #expect(response.value?.contains(#"\e"#) == true)
}

@Test func `moves the Juda kero through shared native wmove`() throws {
    let master = repositoryRoot
        .appending(path: "Content/Local/Ghosts/Juda-System/ghost/master")
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    let windows = MisakaRecordingWindowController()
    let registry = NativeSaoriRegistry(baseDirectoryURL: master, windowController: windows)
    let state = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let session = try NativeMisakaSession(
        masterDirectoryURL: master,
        variableStoreURL: state,
        saoriCaller: registry
    )

    _ = try session.request(request(id: "OnFirstBoot"))
    #expect(windows.moves == [.init(scope: 1, x: 1, speed: 100)])
}

@Test func `initializes every variable in the Juda variable block`() throws {
    let master = repositoryRoot
        .appending(path: "Content/Local/Ghosts/Juda-System/ghost/master")
    guard FileManager.default.fileExists(atPath: master.path) else { return }
    var evaluator = try MisakaEvaluator(dictionary: MisakaDictionary.load(masterDirectoryURL: master))
    _ = evaluator.evaluate(symbol: "$_Variable")
    #expect(evaluator.variables["username"] == ["ユーザ"])
    #expect(evaluator.variables["Rint"] == ["普通"])
    #expect(evaluator.variables["bustmousemovecountmax"] == ["32"])
}

@Test func `loads calls and unloads native SAORI modules`() throws {
    let master = try makeMisakaMaster(dictionary: """
    $_Variable
    {
    {$loadsaori("mciaudior.dll")}
    }

    $OnBoot
    {$saori("mciaudior.dll","load","music\\theme.mp3")}{$saori("mciaudior.dll","loop")}OK

    $OnClose
    {$unloadsaori("mciaudior.dll")}
    """)
    let saori = RecordingSaoriCaller()
    let session = try NativeMisakaSession(masterDirectoryURL: master, saoriCaller: saori)

    #expect(saori.loads == ["mciaudior.dll"])
    #expect(try session.request(request(id: "OnBoot")).value == "OK")
    #expect(saori.calls.count == 2)
    #expect(saori.calls[0].path == "mciaudior.dll")
    #expect(saori.calls[0].arguments == ["load", "music\\theme.mp3"])
    #expect(saori.calls[1].arguments == ["loop"])
    _ = try session.request(request(id: "OnClose"))
    #expect(saori.unloads == ["mciaudior.dll"])
}

private func request(id: String, references: [Int: String] = [:]) -> ShioriRequest {
    var headers = ShioriHeaders([ShioriHeader(name: "ID", value: id)])
    for (index, value) in references {
        headers.append(name: "Reference\(index)", value: value)
    }
    return ShioriRequest(method: "GET", headers: headers)
}

private func makeMisakaMaster(dictionary: String, options: String = "") throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let ini = "dictionaries\n{\nmisaka.txt\n}\n" + options
    try #require(ini.data(using: .shiftJIS)).write(to: root.appending(path: "misaka.ini"))
    try #require(dictionary.data(using: .shiftJIS)).write(to: root.appending(path: "misaka.txt"))
    return root
}

private final class MisakaTestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private var repositoryRoot: URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private final class RecordingSaoriCaller: NativeSaoriCalling, @unchecked Sendable {
    struct Call {
        var path: String
        var arguments: [String]
    }

    var loads: [String] = []
    var unloads: [String] = []
    var calls: [Call] = []

    func load(_ path: String) {
        loads.append(path)
    }

    func unload(_ path: String) {
        unloads.append(path)
    }

    func call(_ path: String, arguments: [String]) -> String {
        calls.append(Call(path: path, arguments: arguments))
        return ""
    }
}

private final class MisakaRecordingWindowController: NativeSaoriWindowControlling, @unchecked Sendable {
    struct Move: Equatable {
        var scope: Int
        var x: Int
        var speed: Int
    }

    var moves: [Move] = []

    func frame(scope _: Int) -> NativeSaoriWindowFrame? {
        nil
    }

    func desktopSize() -> (width: Int, height: Int) {
        (1440, 900)
    }

    func move(scope: Int, x: Int, speed: Int) {
        moves.append(.init(scope: scope, x: x, speed: speed))
    }
}
