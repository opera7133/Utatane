import Testing
@testable import UtatanePlatformMacOS

@Test func `desktop wallpaper initial event uses notification and SSP references`() throws {
    let state = DesktopWallpaperState(screens: [
        DesktopWallpaperScreenState(
            path: "/wallpapers/main.png",
            style: "fill",
            backgroundColor: "12,34,56"
        ),
        DesktopWallpaperScreenState(
            path: "/wallpapers/second.png",
            style: "fit",
            backgroundColor: "0,0,0"
        )
    ])

    let event = try #require(state.initialEvent())
    #expect(event.delivery == .notification)
    #expect(event.references[0] == "init")
    #expect(event.references[1] == "unknown")
    #expect(event.references[2] == "/wallpapers/main.png")
    #expect(event.references[3] == "")
    #expect(event.references[4] == "fill")
    #expect(event.references[5] == "12,34,56")
    #expect(event.references[6] == "0\u{1}/wallpapers/main.png\u{1}fill")
    #expect(event.references[7] == "1\u{1}/wallpapers/second.png\u{1}fit")
}

@Test func `desktop wallpaper detector emits only changes and preserves previous path`() throws {
    var detector = DesktopWallpaperChangeDetector()
    let original = DesktopWallpaperState(screens: [
        DesktopWallpaperScreenState(
            path: "/wallpapers/old.png",
            style: "center",
            backgroundColor: "0,0,0"
        )
    ])
    let updated = DesktopWallpaperState(screens: [
        DesktopWallpaperScreenState(
            path: "/wallpapers/new.png",
            style: "stretch",
            backgroundColor: "255,255,255"
        )
    ])

    #expect(detector.consume(original) == nil)
    #expect(detector.consume(original) == nil)
    let detected = detector.consume(updated)
    let event = try #require(detected)
    #expect(event.delivery == .event)
    #expect(event.references[0] == "update")
    #expect(event.references[1] == "unknown")
    #expect(event.references[2] == "/wallpapers/new.png")
    #expect(event.references[3] == "/wallpapers/old.png")
    #expect(event.references[4] == "stretch")
    #expect(event.references[5] == "255,255,255")
}

@Test func `automatic wallpaper changes remain non-talking notifications`() throws {
    var detector = DesktopWallpaperChangeDetector()
    let first = DesktopWallpaperState(screens: [
        DesktopWallpaperScreenState(path: "/a", style: "fill", backgroundColor: "0,0,0")
    ])
    let second = DesktopWallpaperState(screens: [
        DesktopWallpaperScreenState(path: "/b", style: "fill", backgroundColor: "0,0,0")
    ])
    _ = detector.consume(first)

    let detected = detector.consume(second, cause: .slideshow)
    let event = try #require(detected)
    #expect(event.delivery == .notification)
    #expect(event.references[1] == "slideshow")
}
