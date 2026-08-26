import AppKit
import Testing
@testable import UtatanePlatformMacOS

@Test
@MainActor
func `adjacent links use the glyph under the pointer`() throws {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    textView.textContainerInset = NSSize(width: 12, height: 8)
    textView.textContainer?.lineFragmentPadding = 0
    let text = NSMutableAttributedString(string: "AB", attributes: [.font: NSFont.systemFont(ofSize: 18)])
    text.addAttribute(.link, value: "A", range: NSRange(location: 0, length: 1))
    text.addAttribute(.link, value: "B", range: NSRange(location: 1, length: 1))
    textView.textStorage?.setAttributedString(text)

    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let origin = textView.textContainerOrigin

    func point(nearRightEdgeOfCharacter characterIndex: Int) -> NSPoint {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        let bounds = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return NSPoint(x: origin.x + bounds.maxX - 0.1, y: origin.y + bounds.midY)
    }

    #expect(balloonTextLinkID(at: point(nearRightEdgeOfCharacter: 0), in: textView) == "A")
    #expect(balloonTextLinkID(at: point(nearRightEdgeOfCharacter: 1), in: textView) == "B")
}

@Test
@MainActor
func `links accept a small margin around their glyphs`() throws {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    let text = NSMutableAttributedString(string: "Choice", attributes: [.font: NSFont.systemFont(ofSize: 18)])
    text.addAttribute(.link, value: "choice", range: NSRange(location: 0, length: text.length))
    textView.textStorage?.setAttributedString(text)

    let layoutManager = try #require(textView.layoutManager)
    let textContainer = try #require(textView.textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let bounds = layoutManager.boundingRect(
        forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs),
        in: textContainer
    )
    #expect(balloonTextLinkID(at: NSPoint(x: bounds.midX, y: bounds.maxY + 1), in: textView) == "choice")
}
