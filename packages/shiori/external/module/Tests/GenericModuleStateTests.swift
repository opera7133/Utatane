import Foundation
import Testing
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
