import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test @MainActor
func `FIRST eyesight renders a glyph on white only in stage zero`() throws {
    for stage in [0, 1, -1] {
        let view = FIRSTEyesightView(stage: stage)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var darkPixels = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent < 0.5 {
                    darkPixels += 1
                }
            }
        }
        #expect(view.bounds.size == CGSize(width: 256, height: 256))
        #expect(stage == 0 ? darkPixels > 1000 : darkPixels == 0)
    }
}
