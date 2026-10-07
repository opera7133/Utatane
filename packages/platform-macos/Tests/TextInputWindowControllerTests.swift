import AppKit
import Testing
import UtataneBalloon
@testable import UtatanePlatformMacOS

@MainActor
struct TextInputWindowControllerTests {
    @Test
    func `shows and closes input window`() {
        let controller = TextInputWindowController()
        var committedText: String?
        var cancelled = false

        controller.show(.init(
            id: "test-input",
            title: "テスト入力",
            prompt: "何か入力してください",
            initialValue: "初期値",
            onCommit: { text in
                committedText = text
            },
            onCancel: {
                cancelled = true
            }
        ))

        #expect(committedText == nil)
        #expect(!cancelled)

        controller.close(id: "test-input")
        #expect(cancelled)
    }

    @Test
    func `closes system all input`() {
        let controller = TextInputWindowController()
        var cancelled = false

        controller.show(.init(
            id: "unique-input-id",
            title: "テスト入力",
            onCommit: { _ in },
            onCancel: { cancelled = true }
        ))

        controller.close(id: "__SYSTEM_ALL_INPUT__")
        #expect(cancelled)
    }

    @Test
    func `does not close mismatched ID`() {
        let controller = TextInputWindowController()
        var cancelled = false

        controller.show(.init(
            id: "input-1",
            title: "テスト入力",
            onCommit: { _ in },
            onCancel: { cancelled = true }
        ))

        controller.close(id: "input-2")
        #expect(!cancelled)

        controller.close(id: "input-1")
        #expect(cancelled)
    }

    @Test
    func `persistent input accepts repeated submissions until closed`() {
        let controller = TextInputWindowController()
        var submissions: [String] = []
        var cancelled = false

        controller.show(.init(
            id: "persistent-input",
            title: "継続入力",
            keepsOpenAfterCommit: true,
            onCommit: { submissions.append($0) },
            onCancel: { cancelled = true }
        ))

        controller.submitCurrent("first")
        controller.submitCurrent("second")
        #expect(submissions == ["first", "second"])
        #expect(!cancelled)

        controller.close(id: "persistent-input")
        #expect(cancelled)
    }

    @Test
    func `times out an input window`() async {
        let controller = TextInputWindowController()

        let result = await controller.showPrompt(
            id: "timed-input",
            title: "テスト入力",
            timeoutMilliseconds: 10
        )

        #expect(result == nil)
    }

    @Test
    func `reports timeout separately for SakuraScript input`() async {
        let controller = TextInputWindowController()

        let result = await controller.showInput(
            id: "timed-script-input",
            title: "テスト入力",
            initialValue: "",
            inputKind: .text,
            maximumLength: nil,
            autocompleteValues: [],
            appearance: nil,
            timeoutMilliseconds: 10
        )

        #expect(result == .cancelled(timedOut: true))
    }

    @Test
    func `parses autocomplete values separated by byte one`() {
        let values = TextInputWindowController.autocompleteValues(
            from: "apple\u{1}banana\u{1}apple\u{1}\u{1}cherry"
        )

        #expect(values == ["apple", "banana", "cherry"])
        #expect(TextInputWindowController.autocompleteValues(from: nil).isEmpty)
    }

    @Test
    func `preserves native skin dimensions even when field and buttons need more width`() {
        let balloon = BalloonDefinition(
            directory: URL(filePath: "/tmp/balloon"),
            name: "test",
            originX: 0,
            originY: 0,
            wordWrapPointX: 0,
            wordWrapPointY: 0,
            fontHeight: 12,
            fontColor: BalloonColor(red: 0, green: 0, blue: 0),
            communicateBoxX: 80,
            communicateBoxY: 50,
            communicateBoxWidth: 420,
            communicateBoxHeight: 32
        )
        let appearance = TextInputWindowController.Appearance(balloon: balloon, backgroundImageURL: nil)

        let size = TextInputWindowController.panelSize(
            for: appearance,
            backgroundImageSize: NSSize(width: 400, height: 60)
        )

        #expect(size == NSSize(width: 400, height: 60))
    }

    @Test
    func `compact borderless input remains keyable and renders at its requested size`() throws {
        let controller = TextInputWindowController()
        var cancelled = false
        var appearance: TextInputWindowController.Appearance?
        if let path = ProcessInfo.processInfo.environment["UTATANE_INPUT_BALLOON"] {
            let loader = BalloonLoader()
            let balloon = try loader.load(from: URL(filePath: path))
            let imageID = ProcessInfo.processInfo.environment["UTATANE_INPUT_IMAGE_ID"].flatMap(Int.init) ?? 0
            appearance = .init(balloon: loader.effectiveInputDefinition(for: balloon, id: imageID), backgroundImageURL: loader.inputImageURL(id: imageID, in: balloon))
        }
        controller.show(.init(id: "compact-input", title: "Input", initialValue: "おにいちゃん", appearance: appearance,
                              onCommit: { _ in }, onCancel: { cancelled = true }))
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.canBecomeKey)
        #expect(!window.styleMask.contains(.titled))
        #expect(try #require(window.contentView?.bounds.height) < 100)
        let view = try #require(window.contentView)
        if let appearance, let url = appearance.backgroundImageURL {
            let skin = try TextInputWindowController.loadSkinImage(url, appearance: appearance)
            #expect(view.bounds.size == skin.size)
        }
        view.layoutSubtreeIfNeeded()
        view.display()
        if let path = ProcessInfo.processInfo.environment["UTATANE_INPUT_PREVIEW"] {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: path))
        }
        controller.close()
        #expect(cancelled)
    }

    @Test
    func `input skin uses chroma key PNA and declared self alpha`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 12, bitsPerPixel: 32))
        let data = try #require(bitmap.bitmapData)
        for y in 0 ..< 2 {
            for x in 0 ..< 3 {
                let offset = y * bitmap.bytesPerRow + x * 4
                data[offset] = x == 0 ? 0 : 255
                data[offset + 1] = x == 0 ? 255 : 0
                data[offset + 2] = 0
                data[offset + 3] = 255
            }
        }
        let url = directory.appending(path: "balloonc0.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        var descriptor = "type,balloon\nname,test\n"
        let descriptorURL = directory.appending(path: "descript.txt")
        try descriptor.write(to: descriptorURL, atomically: true, encoding: .utf8)
        let loader = BalloonLoader()
        let appearance = try TextInputWindowController.Appearance(balloon: loader.load(from: directory), backgroundImageURL: url)
        let image = try TextInputWindowController.loadSkinImage(url, appearance: appearance)
        let pixels = try #require(image.representations.first as? NSBitmapImageRep)
        #expect(image.size == NSSize(width: 3, height: 2))
        #expect(try #require(pixels.colorAt(x: 0, y: 0)).alphaComponent == 0)
        let solidAlpha = try #require(pixels.colorAt(x: 1, y: 0)).alphaComponent
        #expect(solidAlpha > 0.99)
        descriptor += "use_self_alpha,1\n"
        try descriptor.write(to: descriptorURL, atomically: true, encoding: .utf8)
        let opaque = try TextInputWindowController.loadSkinImage(url, appearance: .init(balloon: loader.load(from: directory), backgroundImageURL: url))
        let selfAlpha = try #require((opaque.representations.first as? NSBitmapImageRep)?.colorAt(x: 0, y: 0)).alphaComponent
        #expect(selfAlpha > 0.99)
        for y in 0 ..< 2 {
            for x in 0 ..< 3 {
                let offset = y * bitmap.bytesPerRow + x * 4
                for channel in 0 ..< 3 {
                    data[offset + channel] = x == 0 ? 0 : 255
                }
                data[offset + 3] = 255
            }
        }
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url.deletingPathExtension().appendingPathExtension("pna"))
        let masked = try TextInputWindowController.loadSkinImage(url, appearance: appearance)
        #expect(try #require((masked.representations.first as? NSBitmapImageRep)?.colorAt(x: 0, y: 0)).alphaComponent == 0)
    }

    @Test
    func `loads owner drawn button images from the balloon directory`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["ok_up.png", "ok_down.png", "cancel_up.png", "cancel_down.png"] {
            try Data([0]).write(to: directory.appending(path: name))
        }
        let balloon = BalloonDefinition(
            directory: directory,
            name: "test",
            originX: 0,
            originY: 0,
            wordWrapPointX: 0,
            wordWrapPointY: 0,
            fontHeight: 12,
            fontColor: BalloonColor(red: 0, green: 0, blue: 0)
        )

        let appearance = TextInputWindowController.Appearance(balloon: balloon, backgroundImageURL: nil)

        #expect(appearance.confirmButtonUpImageURL?.lastPathComponent == "ok_up.png")
        #expect(appearance.confirmButtonDownImageURL?.lastPathComponent == "ok_down.png")
        #expect(appearance.cancelButtonUpImageURL?.lastPathComponent == "cancel_up.png")
        #expect(appearance.cancelButtonDownImageURL?.lastPathComponent == "cancel_down.png")
    }
}
