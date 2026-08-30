import Foundation
import Testing
@testable import UtataneCore

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
