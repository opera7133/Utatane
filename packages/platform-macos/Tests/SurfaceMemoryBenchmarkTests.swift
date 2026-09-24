import AppKit
import Darwin
import Testing
@testable import UtatanePlatformMacOS
import UtataneShell

/// Opt-in measurement, not a CI timing or process-memory assertion. Run alone in
/// Release with UTATANE_MEMORY_BENCHMARK=1 and --filter SurfaceMemoryBenchmarkTests.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MEMORY_BENCHMARK"] == "1"))
struct SurfaceMemoryBenchmarkTests {
    @Test @MainActor
    func `repeated surface changes`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let png = try makePNG(width: 768, height: 768)
            for id in 0 ..< 64 {
                try png.write(to: directory.appending(path: "surface\(id).png"))
            }
            try makePNG(width: 16, height: 16, color: .red).write(to: directory.appending(path: "overlay.png"))
        }
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
        let composited = ProcessInfo.processInfo.environment["UTATANE_MEMORY_SCENARIO"] != "static"
        let definitions = Dictionary(uniqueKeysWithValues: (0 ..< 64).map { id in
            (id, SurfaceDefinition(id: id, elements: [
                SurfaceElement(id: 0, method: "overlay", filename: "surface\(id).png", x: 0, y: 0),
                SurfaceElement(id: 1, method: "overlay", filename: "overlay.png", x: 8, y: 8)
            ], collisions: [], animations: []))
        })
        let shell = ShellDefinition(directory: directory, surfaces: composited ? definitions : [:], usesSelfAlpha: true)
        let controller = SurfaceWindowController(positionStore: positions)
        defer { controller.resetContent() }
        var samples: [[String: Any]] = []
        let started = ProcessInfo.processInfo.systemUptime
        func record(_ phase: String) throws {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            #expect(result == KERN_SUCCESS)
            samples.append([
                "phase": phase,
                "footprintBytes": info.phys_footprint,
                "residentBytes": info.resident_size,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started
            ])
        }
        try record("beforeShow")
        try autoreleasepool {
            try controller.show(shell: shell, scope: 0, surfaceID: 0)
            try controller.show(shell: shell, scope: 1, surfaceID: 0)
        }
        try record("twoScopes")
        for pass in 1 ... 3 {
            for id in 0 ..< 64 {
                try autoreleasepool {
                    try controller.changeSurface(scope: 0, to: id)
                    try controller.changeSurface(scope: 1, to: id)
                    // Static images may stay lazily decoded. The composited
                    // scenario allocates actual pixel buffers through the renderer.
                    _ = controller.renderedImage(for: 0)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
            }
            try record("pass\(pass)")
        }
        autoreleasepool { controller.resetContent() }
        try record("reset")
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys, .prettyPrinted])
        print("SURFACE_MEMORY_BENCHMARK\n\(String(decoding: data, as: UTF8.self))")
        if let output = ProcessInfo.processInfo.environment["UTATANE_MEMORY_REPORT"] {
            try data.write(to: URL(filePath: output))
        }
    }
}
