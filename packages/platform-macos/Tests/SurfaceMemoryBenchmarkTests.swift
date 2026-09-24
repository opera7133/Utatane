import AppKit
import Darwin
import Testing
@testable import UtatanePlatformMacOS
import UtataneShell

/// Opt-in measurement, not a CI timing or process-memory assertion. Run alone in
/// Release with UTATANE_MEMORY_BENCHMARK=1 and --filter selecting one measurement.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["UTATANE_MEMORY_BENCHMARK"] == "1"))
struct SurfaceMemoryBenchmarkTests {
    @Test @MainActor
    func `repeated history thumbnails`() throws {
        let history = SpeechHistoryStore()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 84, pixelsHigh: 84,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 84 * 4, bitsPerPixel: 32
        ))
        let pixels = try #require(bitmap.bitmapData)
        var seed: UInt32 = 42
        for index in 0 ..< 84 * 84 * 4 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 24)
        }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let started = ProcessInfo.processInfo.systemUptime
        for index in 0 ..< 1000 {
            autoreleasepool {
                // Independent PNG allocations, as produced by each new talk.
                let copy = png.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
                history.append(SpeechHistoryEntry(
                    ghostIdentifier: "benchmark", ghostName: "benchmark", scope: 0,
                    speakerName: "speaker", surfaceID: 0,
                    thumbnailPNGData: copy, text: "Talk \(index)"
                ))
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let buffers = Set(history.entries.compactMap { entry in
            entry.thumbnailPNGData?.withUnsafeBytes { UInt(bitPattern: $0.baseAddress!) }
        })
        let report: [String: Any] = [
            "entries": history.entries.count,
            "pngBytes": png.count,
            "distinctPNGBuffers": buffers.count,
            "retainedPNGBytes": buffers.count * png.count,
            "elapsedSeconds": elapsed
        ]
        #expect(history.entries.count == 500)
        #expect(history.entries.first?.text == "Talk 500")
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print("HISTORY_MEMORY_BENCHMARK\n\(String(decoding: data, as: UTF8.self))")
        if let output = ProcessInfo.processInfo.environment["UTATANE_HISTORY_MEMORY_REPORT"] {
            try data.write(to: URL(filePath: output))
        }
    }

    @Test @MainActor
    func `repeated surface changes`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shell: ShellDefinition
        let surfaceIDs: [Int]
        if let path = ProcessInfo.processInfo.environment["UTATANE_MEMORY_SHELL"] {
            // Read local content in place, without copying it into test fixtures.
            shell = try ShellLoader().load(from: URL(filePath: path))
            surfaceIDs = shell.surfaces.keys.sorted().filter { $0 >= 0 }
            #expect(!surfaceIDs.isEmpty)
        } else {
            try autoreleasepool {
                let png = try makePNG(width: 768, height: 768)
                for id in 0 ..< 64 {
                    try png.write(to: directory.appending(path: "surface\(id).png"))
                }
                try makePNG(width: 16, height: 16).write(to: directory.appending(path: "overlay.png"))
            }
            let composited = ProcessInfo.processInfo.environment["UTATANE_MEMORY_SCENARIO"] != "static"
            let definitions = Dictionary(uniqueKeysWithValues: (0 ..< 64).map { id in
                (id, SurfaceDefinition(id: id, elements: [
                    SurfaceElement(id: 0, method: "overlay", filename: "surface\(id).png", x: 0, y: 0),
                    SurfaceElement(id: 1, method: "overlay", filename: "overlay.png", x: 8, y: 8)
                ], collisions: [], animations: []))
            })
            shell = ShellDefinition(directory: directory, surfaces: composited ? definitions : [:], usesSelfAlpha: true)
            surfaceIDs = Array(0 ..< 64)
        }
        let firstSurfaceID = try #require(surfaceIDs.first)
        let (defaults, positions) = makePositionStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }
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
                "surfaceCount": surfaceIDs.count,
                "footprintBytes": info.phys_footprint,
                "residentBytes": info.resident_size,
                "elapsedSeconds": ProcessInfo.processInfo.systemUptime - started
            ])
        }
        try record("beforeShow")
        try autoreleasepool {
            try controller.show(shell: shell, scope: 0, surfaceID: firstSurfaceID)
            try controller.show(shell: shell, scope: 1, surfaceID: firstSurfaceID)
        }
        try record("twoScopes")
        for pass in 1 ... 3 {
            for id in surfaceIDs {
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
