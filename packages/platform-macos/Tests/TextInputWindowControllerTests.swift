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
    func `sizes a skinned input panel around the declared field and image`() {
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
            backgroundImageSize: NSSize(width: 640, height: 120)
        )

        #expect(size == NSSize(width: 640, height: 166))
    }
}
