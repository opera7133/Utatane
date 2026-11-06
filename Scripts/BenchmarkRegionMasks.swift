// Compile with SurfaceRegionMaskCache.swift, -O -parse-as-library.
// -D BASELINE reproduces the old RGBA dictionary and color/bounds lookup.
// Synthetic collision images only; this is not a full ghost/window benchmark.
import AppKit
import Darwin

@main
struct BenchmarkRegionMasks {
    @MainActor static func main() throws {
        let views = Int(CommandLine.arguments[1])!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let png: Data = autoreleasepool {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32)!
            let data = bitmap.bitmapData!
            for y in 0 ..< 1024 {
                for x in 0 ..< 1024 {
                    let index = y * 4096 + x * 4
                    data[index] = x < 512 ? 255 : 0; data[index + 1] = 0
                    data[index + 2] = x < 512 ? 0 : 255; data[index + 3] = 255
                }
            }
            return bitmap.representation(using: .png, properties: [:])!
        }
        let urls = try (0 ..< views).map { view in
            try (0 ..< 8).map { index in
                let url = root.appendingPathComponent("\(view)-\(index).png")
                try png.write(to: url)
                return url
            }
        }
        var legacy = (0 ..< views).map { _ in [URL: NSBitmapImageRep]() }
        let caches = (0 ..< views).map { _ in SurfaceRegionMaskCache() }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            precondition(result == KERN_SUCCESS)
            return ["residentBytes": info.resident_size, "footprintBytes": info.phys_footprint]
        }
        func seconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        }
        func populate() throws {
            for view in 0 ..< views {
                for url in urls[view] {
                    try autoreleasepool {
                        #if BASELINE
                            guard let bitmap = SurfaceRegionMaskCache.decodeBitmap(url: url) else { throw CocoaError(.fileReadCorruptFile) }
                            legacy[view][url] = bitmap
                        #else
                            guard caches[view].mask(url: url, red: 255, green: 0, blue: 0) != nil else { throw CocoaError(.fileReadCorruptFile) }
                        #endif
                    }
                }
            }
        }
        let before = memory()
        let started = ContinuousClock.now
        try populate()
        let coldSeconds = seconds(started.duration(to: .now))
        let loaded = memory()
        #if BASELINE
            let retained = legacy.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.bytesPerRow * $1.pixelsHigh } }
        #else
            let retained = caches.reduce(0) { $0 + $1.estimatedBytes }
        #endif
        let drawStart = ContinuousClock.now
        var checksum = 0
        // One collision-debug redraw to offscreen bitmaps, without labels/windows.
        for view in 0 ..< views {
            autoreleasepool {
                let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)!
                defer { NSGraphicsContext.restoreGraphicsState() }
                NSColor.systemRed.withAlphaComponent(0.85).setStroke()
                NSColor.systemRed.withAlphaComponent(0.14).setFill()
                for url in urls[view] {
                    let minX: Int, minY: Int, maxX: Int, maxY: Int
                    #if BASELINE
                        let bitmap = legacy[view][url]!
                        let data = bitmap.bitmapData!
                        var firstX = bitmap.pixelsWide, firstY = bitmap.pixelsHigh
                        var lastX = -1, lastY = -1
                        for y in 0 ..< bitmap.pixelsHigh {
                            for x in 0 ..< bitmap.pixelsWide {
                                let index = y * bitmap.bytesPerRow + x * 4
                                if data[index] == 255, data[index + 1] == 0, data[index + 2] == 0 {
                                    firstX = min(firstX, x); firstY = min(firstY, y)
                                    lastX = max(lastX, x); lastY = max(lastY, y)
                                }
                            }
                        }
                        (minX, minY, maxX, maxY) = (firstX, firstY, lastX, lastY)
                    #else
                        let mask = caches[view].mask(url: url, red: 255, green: 0, blue: 0)!
                        let bounds = mask.bounds(inverted: false)!
                        (minX, minY, maxX, maxY) = (bounds.minX, bounds.minY, bounds.maxX, bounds.maxY)
                    #endif
                    checksum += minX + minY + maxX + maxY
                    let path = NSBezierPath(rect: NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
                    path.lineWidth = 1
                    path.fill(); path.stroke()
                }
            }
        }
        let redrawSeconds = seconds(drawStart.duration(to: .now))
        for index in legacy.indices {
            legacy[index].removeAll()
        }
        caches.forEach { $0.setSuspended(true) }
        let cleared = memory()
        caches.forEach { $0.setSuspended(false) }
        let reloadStart = ContinuousClock.now
        try populate()
        let reloadSeconds = seconds(reloadStart.duration(to: .now))
        let result: [String: Any] = ["views": views, "imagesPerView": 8, "imagePixels": 1024 * 1024,
                                     "retainedPayloadBytes": retained, "before": before, "loaded": loaded, "cleared": cleared,
                                     "coldSeconds": coldSeconds, "diagnosticRedrawSeconds": redrawSeconds,
                                     "reloadSeconds": reloadSeconds, "boundsChecksum": checksum]
        try print(String(decoding: JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
    }
}
