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
