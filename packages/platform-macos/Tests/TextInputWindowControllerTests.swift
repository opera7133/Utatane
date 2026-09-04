import AppKit
import Testing
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
    func `parses autocomplete values separated by byte one`() {
        let values = TextInputWindowController.autocompleteValues(
            from: "apple\u{1}banana\u{1}apple\u{1}\u{1}cherry"
        )

        #expect(values == ["apple", "banana", "cherry"])
        #expect(TextInputWindowController.autocompleteValues(from: nil).isEmpty)
    }
}
