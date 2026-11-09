import Foundation
import Testing
import UtataneCore
import UtataneModuleHost
import UtataneShiori

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"] != nil))
func `module bridge saves state outside the ghost with a shared directory`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "module-state-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "ghost/master")
    let state = root.appending(path: "state")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "dictionaries\n{\nmisaka.txt\n}\n".write(
        to: master.appending(path: "misaka.ini"), atomically: true, encoding: .shiftJIS
    )
    try "$_Variable\n{$count=0}\n\n$OnBoot\n{$count++}{$count}".write(
        to: master.appending(path: "misaka.txt"), atomically: true, encoding: .shiftJIS
    )
    let modulePath = try #require(ProcessInfo.processInfo.environment["UTATANE_MISAKA_MODULE"])
    let module = URL(fileURLWithPath: modulePath)
    let request = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"

    let first = try NativeShioriSession(directoryURL: master, moduleURL: module, stateDirectoryURL: state)
    #expect(try ShioriMessageParser.parseResponse(first.request(request)).value == "1")
    try first.close()

    let second = try NativeShioriSession(directoryURL: master, moduleURL: module, stateDirectoryURL: state)
    #expect(try ShioriMessageParser.parseResponse(second.request(request)).value == "2")
    try second.close()
    #expect(FileManager.default.fileExists(atPath: state.appending(path: "misaka-vars.json").path))
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "misaka-vars.json").path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MAE_LOCAL_GHOST"] != nil))
func `mae sample random talk and playback callbacks use the real process host`() throws {
    let source = try URL(fileURLWithPath: #require(ProcessInfo.processInfo.environment["UTATANE_MAE_LOCAL_GHOST"]))
    let root = FileManager.default.temporaryDirectory.appending(path: "真絵 integration \(UUID())")
    let master = root.appending(path: "ghost/master")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: master)
    let module = try #require(try UtataneModuleResolver().moduleURL(for: .mae, masterDirectoryURL: master))
    let session = try NativeShioriSession(directoryURL: master, moduleURL: module, stateDirectoryURL: root.appending(path: "state"))
    defer { try? session.close() }
    let adapter = GhostEventShioriAdapter()
    let boot = try ShioriMessageParser.parseResponse(session.request(adapter.request(for: .boot).serialized()))
    #expect(boot.statusCode == 200)
    var talks = Set<String>()
    for _ in 0 ..< 50 {
        let talk = try ShioriMessageParser.parseResponse(session.request(adapter.request(for: .randomTalk).serialized()))
        #expect(talk.statusCode == 200)
        let script = try #require(talk.value)
        #expect(!script.contains("話すネタが思いつかない"))
        talks.insert(script)
        for id in ["OnTranslate", "OnBalloonClose"] {
            let request = adapter.request(for: .shiori(id: id, references: [0: script]))
            #expect(try ShioriMessageParser.parseResponse(session.request(request.serialized())).statusCode == 204)
        }
    }
    #expect(talks.count > 1)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_DNPROXY_MODULE"] != nil))
func `detected portable DNProxy runs through the real process host`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "DNProxy 日本語 \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "Language: C#\nSourceFiles: Ghost.cs\nMainClass: Portable.Ghost\n".write(to: root.appending(path: "dnproxy.ini"), atomically: true, encoding: .utf8)
    try """
    <configuration><applicationSettings><D.N.Properties.Settings>
    <setting name="AssemblyName"><value>user.dll</value></setting>
    <setting name="MainClass"><value>Portable.Ghost</value></setting>
    <setting name="Protocol"><value>SHIORI/3.0</value></setting>
    </D.N.Properties.Settings></applicationSettings></configuration>
    """.write(to: root.appending(path: "dnproxy.dll.config"), atomically: true, encoding: .utf8)
    try #"""
    using System;
    using System.Text;
    using System.Runtime.InteropServices;
    using Ukagaka.NET.Interfaces;
    namespace Portable {
      public class Ghost : ILoad, IRequest, IUnload {
        public bool load(IntPtr p, int len) { Marshal.FreeHGlobal(p); return true; }
        public bool unload() { return true; }
        public IntPtr request(IntPtr p, ref int len) {
          Marshal.FreeHGlobal(p);
          byte[] bytes = Encoding.UTF8.GetBytes("SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: DNProxy 日本語😀\r\n\r\n");
          len = bytes.Length; IntPtr result = Marshal.AllocHGlobal(len); Marshal.Copy(bytes, 0, result, len); return result;
        }
      }
    }
    """#.write(to: root.appending(path: "Ghost.cs"), atomically: true, encoding: .utf8)
    let descriptor = try #require(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "shiori.dll"))
    #expect(descriptor.id == "dnproxy")
    let kind = try #require(ConventionalShioriKind(shioriFilename: "\(descriptor.id.rawValue).dll"))
    let module = try #require(try UtataneModuleResolver().moduleURL(for: kind, masterDirectoryURL: root))
    let session = try NativeShioriSession(directoryURL: root, moduleURL: module)
    defer { try? session.close() }
    let response = try ShioriMessageParser.parseResponse(session.request(GhostEventShioriAdapter().request(for: .boot).serialized()))
    #expect(response.value == "DNProxy 日本語😀")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_KONOKA_MODULE"] != nil))
func `detected Konoka uses the real process host and shared state directory`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "Konoka 日本語 \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master"), state = root.appending(path: "state")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "ai.txt,e\r\n".write(to: master.appending(path: "konoka.ini"), atomically: true, encoding: .utf8)
    try #"""
    @OnBoot,%(\_save:=counter.7)
    @OnRestore,%(\_load:=counter)
    @OnEcho,%ref0
    @OnTeach,%word:%lasthint\[shortage]
    @OnImport,%(\_load:=legacy)
    """#.write(to: master.appending(path: "ai.txt"), atomically: true, encoding: .shiftJIS)
    try Data("legacy,imported\r\n".utf8).write(to: master.appending(path: "values.dat"))
    let descriptor = try #require(ShioriCatalog.identify(masterDirectory: master, declaredModuleFilename: "renamed.dll"))
    #expect(descriptor.id == "konoka")
    let kind = try #require(ConventionalShioriKind(shioriFilename: "\(descriptor.id.rawValue).dll"))
    let module = try #require(try UtataneModuleResolver().moduleURL(for: kind, masterDirectoryURL: master))
    let first = try NativeShioriSession(directoryURL: master, moduleURL: module, selectedKind: kind, stateDirectoryURL: state)
    defer { try? first.close() }
    let adapter = GhostEventShioriAdapter()
    #expect(try ShioriMessageParser.parseResponse(first.request(adapter.request(for: .boot).serialized())).value == "7\\e")
    let echo = adapter.request(for: .shiori(id: "OnEcho", references: [0: "日本語😀"]))
    #expect(try ShioriMessageParser.parseResponse(first.request(echo.serialized())).value == "日本語😀\\e")
    let teach = adapter.request(for: .shiori(id: "OnTeach", references: [0: "apple", 1: "cat"]))
    let taught = try ShioriMessageParser.parseResponse(first.request(teach.serialized()))
    #expect(taught.statusCode == 311)
    #expect(taught.value == "apple:cat")
    let imported = adapter.request(for: .shiori(id: "OnImport", references: [:]))
    #expect(try ShioriMessageParser.parseResponse(first.request(imported.serialized())).value == "imported\\e")
    try first.close()
    let next = try NativeShioriSession(directoryURL: master, moduleURL: module, selectedKind: kind, stateDirectoryURL: state)
    defer { try? next.close() }
    let restore = adapter.request(for: .shiori(id: "OnRestore", references: [:]))
    #expect(try ShioriMessageParser.parseResponse(next.request(restore.serialized())).value == "7\\e")
    #expect(FileManager.default.fileExists(atPath: state.appending(path: "konoka-state.json").path))
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "konoka-state.json").path))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_HITOMI_MODULE"] != nil))
func `Hitomi Phase 02 runs through the real process host`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "Hitomi 日本語 \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "dict: ai.txt\r\n".write(to: root.appending(path: "kawari.ini"), atomically: true, encoding: .utf8)
    try #"""
    word: 日本語
    ?OnBoot: \0${word}:${0}\e
    ?OnEcho: ${!Reference0}\e
    """#.write(to: root.appending(path: "ai.txt"), atomically: true, encoding: .shiftJIS)
    let descriptor = try #require(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "hitomi.dll"))
    #expect(descriptor.id == "hitomi")
    let module = try #require(try UtataneModuleResolver().moduleURL(for: .hitomi, masterDirectoryURL: root))
    let session = try NativeShioriSession(directoryURL: root, moduleURL: module, selectedKind: .hitomi)
    defer { try? session.close() }
    let adapter = GhostEventShioriAdapter()
    #expect(try ShioriMessageParser.parseResponse(session.request(adapter.request(for: .boot).serialized())).value == "\\0日本語:日本語\\e")
    let echo = adapter.request(for: .shiori(id: "OnEcho", references: [0: "日本語😀"]))
    #expect(try ShioriMessageParser.parseResponse(session.request(echo.serialized())).value == "日本語😀\\e")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_KONOKA_MODULE"] != nil))
func `Konoka standard XDC dictionary runs through the real process host`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "Konoka XDC \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("ai.txt,e\r\n".utf8).write(to: root.appending(path: "konoka.ini"))
    // Original standard DLL's encrypted synthetic @OnBoot event.
    try Data([0xFD, 0x04, 0x3F, 0x25, 0x49, 0x76, 0xA8, 0x93, 0xCF, 0x0E, 0x54, 0xAA, 0xEC, 0x0B, 0x42, 0x62, 0x8F, 0xB2, 0x94, 0x7E, 0x73, 0x5F, 0x44, 0x29, 0x15, 0xFD, 0xC6, 0x7C]).write(to: root.appending(path: "ai.xdc"))
    let module = try #require(try UtataneModuleResolver().moduleURL(for: .konoka, masterDirectoryURL: root))
    let session = try NativeShioriSession(directoryURL: root, moduleURL: module, selectedKind: .konoka)
    defer { try? session.close() }
    let boot = GhostEventShioriAdapter().request(for: .boot).serialized()
    #expect(try ShioriMessageParser.parseResponse(session.request(boot)).value == "合成テスト14\\e")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_HITOMI_MODULE"] != nil))
func `Hitomi learning returns 311 and persists outside the ghost through the real host`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "Hitomi study \(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let master = root.appending(path: "master"), state = root.appending(path: "state")
    try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
    try "dict: ai.txt\r\n".write(to: master.appending(path: "hitomi.ini"), atomically: true, encoding: .utf8)
    try "Hearts.dict: memory.txt\r\n".write(to: master.appending(path: "psy.ini"), atomically: true, encoding: .utf8)
    let memory = Data("Word: cat,0\r\n".utf8)
    try memory.write(to: master.appending(path: "memory.txt"))
    try #"""
    ?#HitomiStudyNewWord : NEW:${!keyword}
    ?#HitomiStudyCommit : SAVED:${!keyword}
    ?#OnCheck : $Hearts.Exist{"apple"}:$Hearts.GetRelation{"apple"}
    """#.write(to: master.appending(path: "ai.txt"), atomically: true, encoding: .utf8)
    let module = try #require(try UtataneModuleResolver().moduleURL(for: .hitomi, masterDirectoryURL: master))
    let first = try NativeShioriSession(directoryURL: master, moduleURL: module, selectedKind: .hitomi, stateDirectoryURL: state)
    defer { try? first.close() }
    let adapter = GhostEventShioriAdapter()
    let begin = adapter.request(for: .shiori(id: "OnTeach", references: [0: "apple"]))
    let answer = try ShioriMessageParser.parseResponse(first.request(begin.serialized()))
    #expect(answer.statusCode == 311)
    #expect(answer.value == "NEW:apple")
    let commit = adapter.request(for: .shiori(id: "OnTeach", references: [0: "apple", 1: "cat", 2: ""]))
    #expect(try ShioriMessageParser.parseResponse(first.request(commit.serialized())).value == "SAVED:apple")
    try first.close()
    let next = try NativeShioriSession(directoryURL: master, moduleURL: module, selectedKind: .hitomi, stateDirectoryURL: state)
    defer { try? next.close() }
    let check = adapter.request(for: .shiori(id: "OnCheck", references: [:]))
    #expect(try ShioriMessageParser.parseResponse(next.request(check.serialized())).value == "apple:cat")
    #expect(FileManager.default.fileExists(atPath: state.appending(path: "hitomi-native-state.json").path))
    #expect(!FileManager.default.fileExists(atPath: master.appending(path: "hitomi-native-state.json").path))
    #expect(try Data(contentsOf: master.appending(path: "memory.txt")) == memory)
}
