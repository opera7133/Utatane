import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Suite(.serialized) @MainActor
struct SurfaceThemedMenuTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "メニュー \(UUID())")
        for directory in ["shell", "ghost"] {
            let path = root.appending(path: directory)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            try makePNG(width: 24, height: 24, color: NSColor(deviceRed: 0, green: directory == "shell" ? 0 : 1, blue: directory == "shell" ? 1 : 0, alpha: 1)).write(to: path.appending(path: "背景.png"))
        }
        try makePNG(width: 8, height: 12, color: NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)).write(to: root.appending(path: "shell/sidebar.png"))
        return root
    }

    @Test func `resource images are ghost relative and override shell paths`() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let values = ["menu.background.bitmap.filename": "背景.png", "menu.font.height": "-18"]
        let shell = try #require(SurfaceMenuAppearance(shellDirectory: root.appending(path: "shell"), shellValues: values,
                                                       ghostDirectory: root.appending(path: "ghost")))
        let resource = try #require(SurfaceMenuAppearance(shellDirectory: root.appending(path: "shell"), shellValues: values,
                                                          ghostDirectory: root.appending(path: "ghost"), overrides: ["menu.background.bitmap.filename": "背景.png"]))
        let shellData = try #require(shell.background?.tiffRepresentation)
        let shellBitmap = try #require(NSBitmapImageRep(data: shellData))
        let resourceData = try #require(resource.background?.tiffRepresentation)
        let resourceBitmap = try #require(NSBitmapImageRep(data: resourceData))
        #expect(shellBitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB)?.blueComponent ?? 0 > 0.9)
        #expect(resourceBitmap.colorAt(x: 5, y: 5)?.usingColorSpace(.deviceRGB)?.greenComponent ?? 0 > 0.9)
        #expect(shell.font.pointSize == 18)
        #expect(SurfaceMenuAppearance(shellDirectory: root, shellValues: ["menu.background.bitmap.filename": "../escape.png"], ghostDirectory: root) == nil)
        #expect(SurfaceMenuAppearance(shellDirectory: root, shellValues: [:], ghostDirectory: root) == nil)
    }

    @Test func `menu drawing keeps sidebar and selection images with edge extension`() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let style = try #require(SurfaceMenuAppearance(shellDirectory: root.appending(path: "shell"), shellValues: [
            "menu.background.bitmap.filename": "背景.png", "menu.foreground.bitmap.filename": "../ghost/背景.png",
            "menu.sidebar.bitmap.filename": "sidebar.png"
        ], ghostDirectory: root.appending(path: "ghost"), overrides: ["menu.foreground.bitmap.filename": "背景.png"]))
        let controller = SurfaceThemedMenuController()
        let view = SurfaceThemedMenuView(items: [.action(title: "一つ目", handler: {}), .action(title: "二つ目", handler: {})], appearance: style, controller: controller, level: 0)
        view.highlight(1, openSubmenu: false)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let path = ProcessInfo.processInfo.environment["UTATANE_MENU_PREVIEW"] {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        }
        let x = bitmap.pixelsWide - 5
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let firstY = Int(view.rowRect(0).midY * scaleY), secondY = Int(view.rowRect(1).midY * scaleY)
        #expect(bitmap.colorAt(x: x, y: firstY)?.usingColorSpace(.deviceRGB)?.blueComponent ?? 0 > 0.9)
        #expect(bitmap.colorAt(x: x, y: secondY)?.usingColorSpace(.deviceRGB)?.greenComponent ?? 0 > 0.9)
        #expect(bitmap.colorAt(x: Int(3 * CGFloat(bitmap.pixelsWide) / view.bounds.width), y: secondY)?.usingColorSpace(.deviceRGB)?.redComponent ?? 0 > 0.9)
    }

    @Test func `keyboard selection skips disabled rows and preserves submenu actions`() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let style = try #require(SurfaceMenuAppearance(shellDirectory: root.appending(path: "shell"), shellValues: ["menu.background.bitmap.filename": "背景.png"], ghostDirectory: root))
        let controller = SurfaceThemedMenuController(); defer { controller.close() }
        var calls = 0
        controller.show(items: [.action(title: "無効", isEnabled: false, handler: { Issue.record("disabled action") }), .separator,
                                .submenu(title: "階層", items: [.action(title: "選択中", isSelected: true, handler: { calls += 1 })]),
                                .action(title: "終了", handler: {})], appearance: style, at: NSPoint(x: 99999, y: -99999))
        let panel = try #require(controller.panels.first)
        let view = try #require(panel.menuView)
        view.move(1)
        #expect(view.selectedIndex == 2)
        view.activate(2)
        #expect(controller.panels.count == 2)
        let child = try #require(controller.panels.last?.menuView)
        child.move(1); child.activate(0)
        #expect(calls == 1)
        #expect(controller.panels.isEmpty)
    }

    @Test func `long menus scroll within the screen and escape closes them`() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let style = try #require(SurfaceMenuAppearance(shellDirectory: root.appending(path: "shell"), shellValues: ["menu.background.bitmap.filename": "背景.png"], ghostDirectory: root))
        let controller = SurfaceThemedMenuController(); defer { controller.close() }
        let screen = try #require(NSScreen.main)
        controller.show(items: (0 ..< 100).map { .action(title: "項目\($0)", handler: {}) }, appearance: style, at: NSPoint(x: screen.visibleFrame.maxX - 2, y: screen.visibleFrame.minY + 2))
        let panel = try #require(controller.panels.first)
        #expect(screen.visibleFrame.contains(panel.frame))
        let scroll = try #require(panel.contentView as? NSScrollView)
        #expect(scroll.hasVerticalScroller)
        let view = try #require(panel.menuView)
        view.move(-1)
        #expect(view.selectedIndex == 99)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        #expect(controller.panels.isEmpty)
    }
}
