import Foundation
import Testing
@testable import UtataneCore

@Test(arguments: ["libexample.dylib", "example.so", "example.bundle", "shiolink.dll", "example.dll"])
func `explicit macOS SHIORI takes priority over dictionary signatures`(filename: String) throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appending(path: "yaya.txt"))
    let descriptor = ShioriCatalog.identify(
        masterDirectory: directory,
        declaredModuleFilename: "yaya.dll",
        macOSModuleFilename: filename
    )
    if filename == "shiolink.dll" {
        #expect(descriptor?.execution == .externalProcess)
    } else if filename == "example.dll" {
        #expect(descriptor == nil)
    } else {
        #expect(descriptor?.execution == .dynamicLibrary)
    }
}

@Test func `identifies known module filename ignoring case`() {
    let descriptor = ShioriCatalog.descriptor(moduleFilename: "NISESHIORI.DLL")

    #expect(descriptor?.id == "nise-shiori")
    #expect(descriptor?.displayName == "偽栞")
    #expect(descriptor?.runtimeRequirement == ShioriDescriptor.RuntimeRequirement.none)
    #expect(descriptor?.support == .supported)
}

@Test func `keeps nise shiori separate from ese shiori`() {
    #expect(ShioriCatalog.descriptor(moduleFilename: "niseshiori.dll")?.id == "nise-shiori")
    #expect(ShioriCatalog.descriptor(moduleFilename: "ese-shiori.dll")?.id == "ese-shiori")
}

@Test func `dictionary signature takes priority over renamed DLL`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data().write(to: directory.appending(path: "misaka.ini"))

    let descriptor = ShioriCatalog.identify(
        masterDirectory: directory,
        declaredModuleFilename: "renamed.dll"
    )

    #expect(descriptor?.id == "misaka")
}

@Test func `shiolink records user provided runtime`() {
    let descriptor = ShioriCatalog.descriptor(moduleFilename: "shiolink.dll")

    #expect(descriptor?.execution == .externalProcess)
    #expect(descriptor?.provisioning == .ghost)
    #expect(descriptor?.runtimeRequirement == .configuredExecutable)
}

@Test func `unknown macOS module uses generic dynamic library support`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let descriptor = ShioriCatalog.identify(
        masterDirectory: directory,
        declaredModuleFilename: "libsomething.dylib"
    )

    #expect(descriptor?.id == "external-posix-shiori")
    #expect(descriptor?.execution == .dynamicLibrary)
    #expect(descriptor?.runtimeRequirement == ShioriDescriptor.RuntimeRequirement.none)
}

@Test func `unknown DLL records Wine compatibility requirement`() throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let descriptor = ShioriCatalog.identify(
        masterDirectory: directory,
        declaredModuleFilename: "unknown.dll"
    )

    #expect(descriptor?.id == "external-windows-shiori")
    #expect(descriptor?.runtimeRequirement == .wine)
}

@Test(arguments: [("mae_corpus.txt", "mae"), ("dnproxy.ini", "dnproxy"), ("dnproxy.dll.config", "dnproxy"), ("ghost.asproj", "aosora")])
func `identifies engines with generic Windows DLL names`(signature: String, expected: String) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "SHIORI 日本語 \(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "shiori.dll")?.id == "external-windows-shiori")
    try Data().write(to: root.appending(path: signature))
    #expect(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "shiori.dll")?.id.rawValue == expected)
    if expected == "dnproxy" {
        #expect(ShioriCatalog.descriptor(id: "dnproxy")?.runtimeRequirement == .configuredExecutable)
        #expect(ShioriCatalog.descriptor(moduleFilename: "engine\\DNPROXY_DEBUG.DLL")?.id == "dnproxy")
    }
    #expect(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "shiori.dll", macOSModuleFilename: "libcustom.dylib")?.id == "external-posix-shiori")
}

@Test func `finds generic native SHIORI with no known dictionary`() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data().write(to: root.appending(path: "shiori.dylib"))
    #expect(ShioriCatalog.identify(masterDirectory: root, declaredModuleFilename: "unknown.dll")?.id == "external-posix-shiori")
    #expect(NativeShioriLibraryLocator.firstExisting(in: NativeShioriLibraryLocator.candidates(moduleID: nil, masterDirectory: root))?.lastPathComponent == "shiori.dylib")
    #expect(NativeShioriLibraryLocator.declaredURL("../escape.dll", in: root) == nil)
    #expect(NativeShioriLibraryLocator.declaredURL("/tmp/escape.dll", in: root) == nil)
    #expect(NativeShioriLibraryLocator.candidates(moduleID: "../escape", nativeRoot: root).isEmpty)
}
