import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor
func `layout presets preserve a multi ghost scene across persistence and renaming`() throws {
    let suite = "layout-presets." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let ghosts = ["primary", "called"].map { name in
        LayoutPresetGhost(
            ghostPath: "/ghosts/\(name)", shellPath: "/ghosts/\(name)/shell/alternate", balloonPath: "/balloons/example",
            positions: [0: CGPoint(x: 120.5, y: 40), 1: CGPoint(x: 420, y: 41)],
            balloonPositions: [0: CGPoint(x: 135, y: 200)],
            stageFrame: CGRect(x: 30, y: 40, width: 1000, height: 700)
        )
    }
    let preset = LayoutPreset(
        name: "Streaming", ghosts: ghosts, windowMode: "shared",
        shellPercent: 80, balloonPercent: 90, textPercent: 110, linksBalloonScale: false
    )
    let store = LayoutPresetStore(defaults: defaults)
    store.save(preset)
    let reopened = LayoutPresetStore(defaults: defaults)
    #expect(reopened.presets == [preset])
    reopened.rename(preset.id, to: "  Desktop  ")
    let renamed = try #require(LayoutPresetStore(defaults: defaults).presets.first)
    #expect(renamed.name == "Desktop")
    #expect(renamed.ghosts == ghosts)
    #expect(renamed.shellPercent == 80)
    reopened.remove(preset.id)
    #expect(LayoutPresetStore(defaults: defaults).presets.isEmpty)
}

@Test @MainActor
func `overwriting a layout preset retains its identity and does not create another entry`() throws {
    let suite = "layout-presets." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = LayoutPresetStore(defaults: defaults)
    let id = UUID()
    for scale in [100, 70] {
        store.save(LayoutPreset(
            id: id, name: "Example", ghosts: [], windowMode: "off",
            shellPercent: scale, balloonPercent: 100, textPercent: 100, linksBalloonScale: true
        ))
    }
    #expect(store.presets.count == 1)
    #expect(store.presets.first?.shellPercent == 70)
}

@Test
func `SHIORI diagnosis reports a missing file without pretending it was initialized`() async {
    let target = SHIORIDiagnosticTarget(
        id: "/example", name: "Example", selectedFilename: "libexample.dylib", macOSOverride: "libexample.dylib",
        moduleURL: URL(filePath: "/tmp/\(UUID().uuidString).dylib"), runtimeResult: "No startup attempt"
    )
    let report = await SHIORIModuleInspector.inspect(target)
    #expect(report.contains("Module file does not exist"))
    #expect(report.contains("No startup attempt"))
    #expect(report.contains("shiori.macos: libexample.dylib"))
}

@Test
func `SHIORI static diagnosis detects exported ABI symbols without loading the module`() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appending(path: "example.c")
    let module = root.appending(path: "libexample.dylib")
    let marker = root.appending(path: "loaded")
    try Data("""
    #include <stdio.h>
    #include <stdint.h>
    __attribute__((constructor)) static void loaded(void) { FILE *f = fopen("\(marker.path)", "w"); if (f) fclose(f); }
    int32_t loadu(void *p, int32_t n) { return 1; }
    int32_t unload(void) { return 1; }
    void *request(void *p, int32_t *n) { return 0; }
    """.utf8).write(to: source)
    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/clang")
    compiler.arguments = ["-dynamiclib", source.path, "-o", module.path]
    try compiler.run()
    compiler.waitUntilExit()
    #expect(compiler.terminationStatus == 0)
    let target = SHIORIDiagnosticTarget(
        id: root.path, name: "Example", selectedFilename: module.lastPathComponent,
        macOSOverride: module.lastPathComponent, moduleURL: module, runtimeResult: "Not started"
    )
    let report = await SHIORIModuleInspector.inspect(target)
    #expect(report.contains("loadu: present"))
    #expect(report.contains("load: not found"))
    #expect(report.contains("request: present"))
    #expect(report.contains("unload: present"))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}
